# Khata Clone — College Project (Clean-Room)

End-to-end Khatabook-**inspired** ledger clone. All code is original, written from a
high-level static analysis of the APK. **No decompiled code is copied.**

Research first, code second — start with `docs/`:
- `docs/01-app-research.md` — what the APK is made of (layers, 50 feature modules,
  SDKs, components, offline-first evidence)
- `docs/02-workflows.md` — reconstructed flows W1–W10 (launch, login, AppLock,
  ledger, cashbook, bills, collections, staff, money verticals, backup)
- `docs/03-clone-architecture.md` — how each finding maps to this repo
- `docs/04-demo-viva.md` — 10-minute demo script + viva Q&A
- `docs/05-selfhost-deploy.md` — online hosting (**Render = current test host**, parked
  Oracle Always-Free track) + account-based sync on both phones + own-server migration

## What was learned from the APK (static analysis only)

File: `D:\khatabook\AF3DWB...` — 54 MB, ZIP/APK
- Real app: **Khatabook v8.43.0** (`com.khatabook.bahikhata.*`, minSdk 22, targetSdk 35)
- Manifest package is repackaged as `com.vaibhavkalpe.android.khatabook` (prefer the Play Store original)
- 1141 layouts, 33 activities, 17 services, 19 receivers; Kotlin + Dagger/Hilt
- Architecture: `appscommon/` (auth/analytics/config managers) + `core/` (sync,
  network) + `framework/` (MVI state machine) + `feature/*` (~50 modules) +
  `kbloan/` + `kytesdk/` (SMS)
- Auth core: `AuthenticationManagerImpl` (`getToken`/`refreshAccessTokenIfRequired`/
  `verify`), Firebase + Truecaller providers, `AuthenticationService`
  (`requestOtp`/`login`/`refreshToken`/`migrateToNewAuthentication`)
- Backend: `api.khatabook.com`, Razorpay (`rzp_live_*`), Truecaller, Firebase,
  Rudderstack/CleverTap/Singular fan-out per `analytic_config.json`
- Offline-first: Room + `SyncableEntity`/`TwoWaySyncableDto`/`BookVsServerSeq` +
  WorkManager; invoices render locally from `assets/invoices/*.html` in a WebView

## What's built (all 8 phases)

| Area | Features |
|---|---|
| Login (password, zero SMS) | Phone → password (register first device, login on any device — same number sees same books) → profile onboarding → PIN setup → PIN unlock on every launch; 15-min JWT + rotating refresh with reuse detection. OTP/SMS flow parked commented (see `docs/05-selfhost-deploy.md` §12) |
| Ledger | Customers, CREDIT (udhaar given) / DEBIT (payment), balance = opening + ΣC − ΣD, search, cashbook summary, day-wise report, CSV export |
| Staff (W8) | Invite by phone (viewer/entry/manager), OTP-claim, book switcher, per-endpoint permission middleware, owner activity feed, revoke |
| Bills (W6) | GST slab math, multi-item creator with live total, offline HTML invoice + thermal receipt preview, share, business-seal stamp toggle |
| Collections (W7) | Dues picker, SMS/WhatsApp/call reminders, mock payment links, simulate-pay auto-ledger entry |
| Business (P8-10) | Refer & earn (invite code, claim, ₹ reward stats), business card with scannable vCard QR, business profile editor, cash register / day-book report, per-txn SMS toggle |
| Safety (W10) | Recycle bin (restore/purge), full JSON backup export + validated overwrite-import |
| Polish | English/Hindi toggle, role-gated UI everywhere the API gates |

## Repo layout

```
khata_clone/
  docs/      01-app-research.md … 04-demo-viva.md
  scripts/   ci.ps1  (backend tests + flutter analyze + flutter tests)
  backend/   Node 22+ + Express + node:sqlite (built-in, no native build)
    src/db.js src/utils/{jwt,otp,invoice}.js src/middleware/{common,staff}.js
    src/routes/{auth,customers,transactions,bills,reports,staff,collections,recycle,backup,business}.js
    data/seed/*.json  (gst, units, categories observed in APK assets)
    tests/api.test.js
  app/       Flutter 3.47 (Provider + http + webview_flutter + share_plus + qr_flutter)
    lib/core/{api_client,auth_storage,state,lang}.dart
    lib/features/{auth,home,customers,staff,bills,collections,safety,business,money}/
    assets/business_categories.json
```

## Install the mobile app (APK — no build needed)

Ready file: **`D:\khatabook\khata-clone-v1.1.0-password-lan.apk`** (53 MB, signed,
password login, API = `http://10.26.60.8:8080` — rebuild if the PC's Wi-Fi IP changes).

> LAN testing only (laptop must run the backend, same Wi-Fi). For anywhere-sync
> without the laptop, follow `docs/05-selfhost-deploy.md` (Oracle free VM) and
> rebuild once with `--dart-define=API_BASE_URL=https://<your-domain>`.

1. On this PC: `cd D:\khatabook\khata_clone\backend; npm install; npm start` (keep it running).
2. Phone on the **same Wi-Fi** as this PC → copy the APK over (WhatsApp/Drive/USB) → tap → Allow install → Install.
3. Open **Khata Clone** → enter number → **Create account** (password min 8 chars) → profile → PIN.
   (Seeded LAN demo: `9999999999` — register it or use any number; OTP flow is parked.)
4. If the app can't reach the server: PC and phone must share Wi-Fi; if the PC's
   Wi-Fi IP changes, rebuild: `flutter build apk --release --dart-define=API_BASE_URL=http://<NEW-IP>:8080`.

## Run backend (5 min demo)

```powershell
cd D:\khatabook\khata_clone\backend
Copy-Item .env.example .env   # ALLOW_DEMO_OTP=1, OTP_FIXED=123456
npm install
npm test                      # ALL TESTS PASSED
npm start                     # http://localhost:8080/health
```

Key API (all staff-aware via `X-Book-Owner-Id`):
- `POST /auth/register` (phone+password, 201) · `POST /auth/login` → `{access, refresh, user, is_new, staff_books}`
- `POST /auth/request-otp` · `POST /auth/verify-otp` — PARKED (SMS seam, commented)
- `POST /auth/refresh` (rotation) · `GET /auth/me` · `PATCH /auth/profile`
- `POST /auth/{pin-set,pin-verify,pin-remove}` · `POST /auth/logout`
- `GET/POST /customers` (+`/:id`, `DELETE` = soft) · `POST /transactions` · `GET /transactions/summary/cashbook`
- `POST /bills` · `GET /bills/:id/html?template=standard|thermal` · `GET /reports/summary` · `GET /reports/ledger.csv`
- `POST /staff/invite|role|revoke` · `GET /staff/activity`
- `POST /collections/links` · `POST /collections/links/:ref/pay` · `POST|GET /collections/reminders`
- `GET /recycle` · `POST /recycle/.../restore` · `DELETE /recycle/.../permanent`
- `GET /backup/export` · `POST /backup/import` (owner-only)

Demo account after seed (LAN testing only, never on a server): phone `9999999999`, password `demo1234`, PIN `1234`.

## Run Flutter app

```powershell
cd D:\khatabook\khata_clone\app
flutter pub get
flutter analyze        # 1 info only
flutter test           # All tests passed!
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # emulator
# physical phone on same Wi-Fi, e.g.:
# flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
```

Full gate in one shot: `powershell -ExecutionPolicy Bypass -File scripts\ci.ps1`.

## Production hardening checklist (for viva)

- [x] Rate limits, helmet, zod validation, prod JWT-secret guard
- [ ] Real OTP provider (Firebase/Truecaller) + Play Integrity; `ALLOW_DEMO_OTP=0`
- [ ] `flutter_secure_storage` + biometric (`local_auth`) for AppLock parity
- [ ] Offline write queue + `sync_seq` (BookVsServerSeq equivalent) for 10k+ txns
- [ ] Bluetooth thermal printing (receipt HTML already thermal-ready)

## Disclaimer

For education only. Khatabook™ belongs to its owners. Do not publish this clone with
their branding, icon, or copied assets.
