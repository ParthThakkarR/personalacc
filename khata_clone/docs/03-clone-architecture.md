# 03 — Clone Architecture (clean-room mapping)

## Backend (Node 22 + Express + `node:sqlite`) — mirrors AuthenticationService + ledgers

```
src/
  index.js            composition root (helmet/cors/rate-limit → routes → errorHandler)
  db.js               schema + seed (users/otp/refresh/customers/transactions/bills)
  utils/jwt.js        access (15m) + refresh (30d) helpers
  utils/otp.js        OTP generate/verify/resend-cooldown/attempt-limit (NEW)
  middleware/common.js requireAuth (auto-refresh-aware) + validate + errorHandler
  routes/
    auth.js           request-otp → verify-otp → refresh → me → profile → pin-* → logout
    customers.js      khata parties + balances
    transactions.js   CREDIT/DEBIT ledger + cashbook summary
    bills.js          GST invoice math (slab table from APK assets)
    reports.js        day-wise/customer summary + ledger.csv
```

### Auth contract (proper system, cf. W2)

| Endpoint | In | Out | Rules |
|---|---|---|---|
| `POST /auth/request-otp` | `{phone}` | `{ok, resend_after_s}` (+`demo_code` only if `ALLOW_DEMO_OTP=1`) | 60 s resend cooldown, 5-min TTL, ≤5 tries/15 min per phone (429) |
| `POST /auth/verify-otp` | `{phone, code}` | `{access, refresh, user, is_new}` | ≤5 attempts → OTP invalidated (401); new users get `is_new:true` → profile step |
| `POST /auth/refresh` | `{refresh}` | `{access, refresh}` | rotation: old refresh revoked, reuse → revoke family (401) |
| `GET /auth/me` | Bearer | `{user}` | guard for Flutter `AuthGuard` |
| `PATCH /auth/profile` | `{name, business_name, business_category?}` | `{user}` | completes onboarding |
| `POST /auth/pin-set` | `{pin}` (+`current_pin` if set) | `{ok}` | 4–8 digits, bcrypt |
| `POST /auth/pin-verify` | `{pin}` | `{ok}` | ≤5 fails → `locked_until` (mirrors `app_locked_timer`) |
| `POST /auth/logout` | `{refresh?}` | `{ok}` | revokes refresh family, client clears storage |

Access JWT: 15 min (`sub`, `phone`). Refresh: opaque 256-bit, sha256-stored, 30 d.

### Data model (subset of SyncableEntity world)

- `users(id, phone UNIQUE, name, business_name, business_category, pin_hash, pin_fail_count, pin_locked_until, created_at)`
- `otp_codes(phone PK, code_hash, expires_at, attempts, resend_after, requested_at)`
- `refresh_tokens(id, user_id, token_hash UNIQUE, expires_at, revoked_at, replaced_by, created_at)`
- `customers(id, user_id→users, name, phone, address, opening_balance, created_at)`
- `transactions(id, user_id, customer_id, kind∈{CREDIT,DEBIT}, amount>0, note, txn_date, created_at)` + index `(user_id, customer_id)`
- `bills/bill_items` as before. Balance rule: `opening + Σ(CREDIT) − Σ(DEBIT)` —
  CREDIT = shopkeeper gave udhaar (receivable), matching app semantics.

## Mobile (Flutter, Provider) — mirrors feature/* + BaseVM state machines

```
lib/
  main.dart                        providers + AuthGuard (init → me → route)
  core/api_client.dart             access attach + single-flight 401→refresh→retry
  core/auth_storage.dart           secure token store (NEW)
  core/state.dart                  AuthState/KhataState (loading/error/data tri-state)
  features/auth/
    phone_screen.dart              10-digit validation → request-otp + cooldown UI
    otp_screen.dart                6-digit entry + countdown (login_waiting_for_code)
    profile_setup_screen.dart      name/business/category (business_categories.json)
    pin_setup_screen.dart          PIN + confirm (Khatabook-PIN mode)
    pin_unlock_screen.dart         unlock + lockout message (app_locked_timer)
  features/home/home_screen.dart
  features/customers/customer_detail_screen.dart
```

Flow: `Phone → OTP → (is_new ? Profile → PIN : [PIN set? Home : PIN])`, guarded by
`GET /auth/me` on launch. Dio-style interceptor is hand-rolled in `ApiClient`
(single-flight refresh) to avoid new native deps.

## Deliberately out of scope (documented, not cloned)

Loans/Invest/KYC/Credit-score WebViews, Truecaller/Firebase SDKs (mock OTP interface
kept), CleverTap/Singular/Rudderstack fan-out (single analytics hook point left),
Bluetooth printing (receipt-HTML export kept, matching `assets/invoices/` approach),
multi-book sync protocol (schema reserves `note`/`txn_date`; `BookVsServerSeq`
equivalent = future `sync_seq` column).
