# 02 — Workflows (reconstructed from manifest + strings + layouts + classes)

## W1. Cold start (`AppLandingState`: Init → … → Home)

```
SplashActivity → StartTimeProvider/ColdStartupDetector
  → AppLandingState ∈ {Init, OnBoarding, NewBook, FirstTimeSync, DatabaseMigration, Home}
  → MainActivity (seasonal variant: .Diwali/.Christmas/.NewYear)
```

## W2. Registration / login (the flow you asked to clone properly)

```
pre_login_language (item: pre_login_language_rv_item)
  → layout_login_intro → layout_login_number_input (+ trust badge, divider)
  → requestOtp  [TrueCallerAuthentication.request (+Play Integrity) | FirebaseAuthentication.request]
  → layout_login_otp / layout_login_verification (+ layout_login_error_state)
  → auto-read SMS (RECEIVE_SMS + kytesdk) or manual entry
  → makeVerify → AuthenticationService.login → LoginResponse
       { KbAuthenticationAccount, KbAuthenticationSession(access+refresh) }
  → migrateToNewAuthentication (legacy sessions)
  → business onboarding: fragment_business_and_owner_name → business_type →
     business_category (assets/business_categories.json) → business_address →
     business_location (+ pincode) → profile_picture
  → on_start_permissions: contacts → SMS → phone → location → notification
     (fragment_permission*, all_permissions*.mp4, permission_bs_anim.lottie)
  → FirstTimeSync (BookVsServerSeq) → Home
Resend: requestAgain; UI shows login_waiting_for_code ("Resend OTP in %1$s s").
```

## W3. AppLock (device-level, independent of login tokens)

```
Settings → "App and Data Lock" → mode ∈ {Phone Lock (biometric/PIN), Khatabook PIN}
Enroll/change/remove all require authentication first.
Wrong PIN → app_lock_wrong_pin_{1,2} → app_locked_timer lockout.
Migration bottom-sheet exists for lock-scheme upgrades.
```

## W4. Khata ledger (core loop)

```
Home (fragment_home_customer, KHATA_PAGE banner slot) → search/filter customer
→ fragment_customer_khata_header (balance) → add CREDIT (udhaar given) / DEBIT (payment)
→ TwoWaySyncableDto → server seq → Home totals + userdashboard
Delete → recyclebin (recoverable) / deletekhata (permanent).
```

## W5. Cashbook

```
cashregister → day-wise entries (fragment_day_wise_report[_detail]) → cash_book_welcome_msg
(first-run) → totals into Home.
```

## W6. Bills / invoices (offline-first)

```
fragment_add_bill → bill_add_party_layout → bill_add_items_layout (+ inventory picker,
units from inventory_unit.json) → bill_gst_bottom_sheet (slabs: gst_slabs.json) →
discount/charges → WebView preview (assets/invoices/invoice-N.html + data-loader.js)
→ save/share/print (printer module, Bluetooth) → GSTR fragments for returns.
```

## W7. Collections (why sticky notifications + SMS/WhatsApp perms exist)

```
bulkreminder/callreminder/paymentreminder → customer list → channel ∈ {SMS, WhatsApp,
call} → payment link/QR (payment_link.json, Razorpay/UPI) → auto ledger entry
("entry in khata, automatically") → StickyNotifBroadCastReceiver follow-ups.
```

## W8. Staff + access control

```
stafftab → add staff → accesscontrol roles (add/view/totals/edit permissions)
→ child login (ac_child_onboarding_*) → owner alerts on staff entries.
```

## W9. Money verticals (WebView-hosted, out of clone scope)

```
subscription/PaymentMethodActivity (Razorpay) → Premium
kbinvest → invest.khatabook.com | kbloan → loans-web.khatabook.com (+ KYC:
Aadhaar OTP → PAN verify → bank/IFSC verify) | credit-score (consent + OTP).
```

## W10. Backup / platform

```
backuprestore (Google Drive, khatabook.com/recover) → logout (clearAppData) →
recyclebin. Analytics fan-out on every event per analytic_config.json.
```
