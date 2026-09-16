# 04 — Demo script + viva kit (10 minutes, in order)

## 0. Start (2 min before the demo)

```powershell
cd D:\khatabook\khata_clone\backend
Copy-Item .env.example .env   # ALLOW_DEMO_OTP=1, OTP_FIXED=123456
npm install; npm start        # http://localhost:8080/health
```

```powershell
cd D:\khatabook\khata_clone\app
flutter pub get; flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Seeded demo: phone `9999999999`, OTP `123456`, PIN `1234`.

## 1. Login story (2 min)

Phone → OTP with live resend countdown → first login lands on business profile
(name/business/category autocomplete from the APK's own category list) → PIN setup
→ every restart asks PIN (wrong PIN 5× shows the lockout, mirroring AppLock).

Say: "OTP codes are bcrypt-hashed with cooldowns and attempt limits; sessions are
15-minute JWTs plus rotating refresh tokens with reuse detection."

## 2. Ledger story (2 min)

Add customer → Give ₹1000 udhaar → Receive ₹400 → balance ₹600. Pull to refresh.
Delete the customer → More → Recycle bin → Restore → balance intact. Then purge.

Say: "Deletes are soft deletes; CREDIT means I gave udhaar, balance is
opening + credits − debits."

## 3. Bills story (2 min)

Bills → New bill → 2 items → GST slab → live total → Save → Preview invoice
(offline HTML) → Thermal receipt → Share.

Say: "Invoices render from local templates like the original's WebView approach;
the HTML string is cached so preview works in airplane mode."

## 4. Staff story (2 min)

Staff & access → invite second number as viewer → log in as staff → book switcher
appears → viewer sees list but no add button and totals hidden → promote to entry
→ add works → owner's Staff activity shows the entry → revoke → access gone.

Say: "Role middleware resolves X-Book-Owner-Id to permissions on every request;
the UI hides what the API forbids."

## 5. Collections story (1 min)

Collections → tick dues → WhatsApp remind → payment link → Simulate pay →
ledger auto-entry. Say: "Mirrors the real payment-link loop, mocked for demo."

## 6. Backup + Hindi (1 min)

More → Backup: export JSON (clipboard) → restore with double confirm.
More → हिन्दी: whole chrome flips language.

## 7. Engagement + business identity (2 min)

More → Refer & earn: green card shows my invite code (copy/share), bonus per
friend, friends joined, total earned → paste a friend's code → Claim → snackbar
shows ₹100 awarded. More → Business card: gradient card + scannable QR (vCard
payload served by GET /business/card) → share/copy. More → Cash book: date
pager, given/received/net for the day; appbar SMS icon toggles per-txn receipt.
More → Business profile: edit name/business/category → Save. Invoices → open a
bill → stamp (seal) icon adds a business seal to the PDF.

Say: "Referral is a real `referrals` table + one-time claim per user; QR is a
pure-Dart render; seal is a template flag in the invoice renderer."

## Likely viva questions (2-minute answers each)

1. **Did you copy the APK?** No — resource-only decode + string mining; see
   `docs/01-app-research.md`. All code is clean-room.
2. **Why not Firebase?** College demo must run offline with zero keys; the OTP
   module is a seam (`utils/otp.js`) ready for a real provider.
3. **Refresh reuse?** Rotation stores `replaced_by`; presenting a rotated token
   revokes the family — theft containment.
4. **Staff security?** Server-side `resolveBook` + `requirePerm` per endpoint;
   UI gating is cosmetic, API gating is real (viewer POST → 403, tested).
5. **GST math?** `total = subtotal + subtotal·igst/100 − discount`, slab table
   from the APK's `gst_slabs.json`.
6. **Scale?** SQLite WAL + `(user_id, customer_id)` index; swap `db.js` for
   Postgres; add `sync_seq` for the `BookVsServerSeq` protocol later.
7. **What would you build next?** Offline write queue + Bluetooth thermal print +
   `flutter_secure_storage` for tokens.
