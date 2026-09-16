# 01 — Khatabook APK Research (static analysis, no source copied)

Method: Apktool `decode -s` (manifest + resources only, no smali), dex ASCII-string
mining for class descriptors + URLs, `res/values/strings.xml` + layout-name taxonomy.
Nothing below reproduces proprietary code — only structure, names and config facts.

## 1. Identity

| Fact | Evidence |
|---|---|
| Real app | Khatabook **v8.43.0**, versionCode 804300 (`apk_decoded/apktool.yml`) |
| Code namespace | `com.khatabook.bahikhata.*` activities, `com.khatabook.*` framework, `in.khatabook.*` KYC (`AndroidManifest.xml`) |
| Manifest package | `com.vaibhavkalpe.android.khatabook` → **repackaged**, not the Play Store signer |
| SDK | minSdk 22, targetSdk 35, compileSdk 35 |
| Size | 54 MB APK, 5369 zip entries, 4 dex files (~34 MB code), 4630 res files, 1141 layouts |
| Native libs | Only generic: `libandroidx.graphics.path`, `libimage_processing_util_jni`, `libsurface_util_jni`, `libtoolChecker` — ledger logic is Kotlin, not NDK |
| Kotlin | Gradle 8.6 + Kotlin 2.1.0, Hilt/Dagger (`MainActivityFragmentBuilder`, `MainActivityModule`) |

## 2. Layered architecture (from dex class descriptors)

```
appscommon/                     shared SDK layer (reused across Khatabook apps)
  authenticationmanager/        client/ + data/ + domain/ + framework/
  analyticsclient/              client/ + data/ + domain/
  configmanager/                client/ + data/ + domain/ + framework/database (Room)
core/                           syncmanager (60+ classes), networkmanager
framework/                      mvistatemachine, basemodule, analyticsclientmanager,
                                locationmanager, syncmanager, pushnotificationreceiver
bahikhata/app/common/base/      BaseActivity/BaseFragment/BaseVM, RecyclerViewAdapter,
  data/{local,remote}             SyncableEntity, OneWay/TwoWaySyncableDto, BookVsServerSeq
  domain/                         NewBaseRepository
  presentation/                   MVI state machine: BaseEvent/BaseState/Feature/SubFeature
bahikhata/app/feature/          ~50 feature modules (see §4)
kbloan/                         loans SDK: activity, webview, camera, upload/download,
                                permission, resourceCaching
kytesdk/                        SMS-reading SDK (newsms, model, data, analytics)
```

Every feature follows **client / data / domain / presentation** (clean architecture + MVI).

## 3. Auth internals (class names only)

- `AuthenticationManagerImpl`: `getToken`, `refreshAccessTokenIfRequired`, `verify`,
  `clearAppData`, `handleMigration`
- Providers: `FirebaseAuthentication` (`request`/`requestAgain`/`makeVerify`),
  `TrueCallerAuthentication` (`request` + `startPlayIntegrity`), plus `old/*` legacy
  variants for migration
- `AuthenticationService` (Retrofit-style, all POST): `requestOtp`, `oldRequestOtp`,
  `login`, `oldLogin`, `refreshToken`, `migrateToNewAuthentication`
- Entities: `KbAuthenticationAccount`, `KbAuthenticationSession`, `LoginResponse`
- Strings: `login_retry_resend_code` ("Resend OTP"),
  `login_waiting_for_code` ("Resend OTP in %1$s seconds") → resend cooldown is
  server-driven with a visible countdown
- AppLock is separate from login: `AppLockActivity`, `AppLockHelper`, Khatabook-PIN
  vs Phone-Lock modes, wrong-PIN counters (`app_lock_wrong_pin_1/2`), lockout timer
  (`app_locked_timer`: "App locked for %1$s. Try again in %2$s")

## 4. Feature modules (`bahikhata/app/feature/*`, class counts)

Core ledger: `khata` (245), `addcustomer` (134), `book` (29), `deletekhata` (4),
`ledgerattachment` (21), `passbook` (41), `userdashboard` (51), `home` (170),
`main` (100), `report` (52), `cashregister`/`cash_book` (75), `money` (39).
Billing: `billbook` (857 — biggest), `inventory` (142), `finance` (646).
Engagement: `bulkreminder` (368), `callreminder` (230), `paymentreminder` (23),
`bulksmsreminder` (84), `txnsms` (142), `refernearn` (69), `collection` (45).
Business: `businessprofile` (125), `businessseal` (63), `businesscard` (8),
`stafftab` (218), `accesscontrol` (124), `profile` (44).
Money: `subscription` (65), `kbinvest` (42), `mobilepro` (179).
Platform: `onboarding` (78), `backuprestore` (45), `recyclebin` (15), `logout` (13),
`printer` (10), `marketplace` (9), `services` (149), `more` (65), `admob` (29).

## 5. Backend surface (dex URLs)

- `https://api.khatabook.com` — primary API (auth, khata, bills)
- `https://assets.khatabook.com/...` + `khatabook-assets.s3.ap-south-1` — Lottie/CDN
- `https://rudderstack-service.khatabook.com` (+ `api.rudderlabs.com`) — analytics
- `https://loans-web.khatabook.com`, `https://invest.khatabook.com`,
  `https://desktop.khatabook.com/subscribe` — WebViews (`KbLoanLoanActivity`)
- `https://api.razorpay.com` + `rzp_live_*` key in manifest — payments
- Truecaller SDK (`outline.truecaller.com`), Singular (`sdk-api-v1.singular.net`),
  CleverTap, Plotline (`api.plotline.so`), AppStorys (`backend.appstorys.com`),
  Finbox (`approvals-api.getsimpl.com`), Facebook, AdMob (`ca-app-pub-...`)
- Analytics fan-out per event (`assets/analytic_config.json`):
  each event lists `rudder_stack / clever_tap / firebase / singular / plot_line /
  app_storys / segment` booleans + `frequency` — one `AnalyticsConfigDto` drives it

## 6. Components

- 33 activities (Splash → Main; DeepLinking; Diwali/Christmas/NewYear Main variants;
  Plotline; KbInvest; PaymentMethod; KYC; KbLoan; Facebook; Firebase Auth; CleverTap
  inbox; AdMob; Razorpay Deeplink; `KbDebugActivity`)
- 17 services: WorkManager (SystemAlarm/SystemJob), Firebase Messaging +
  `PnService` (own push receiver), CleverTap push, AdMob, Auth revocation
- 19 receivers: boot, connectivity, CleverTap templates, `StickyNotifBroadCastReceiver`
  (collection sticky notification), loan resource-caching
- Providers: app FileProvider, `core.database` provider (Room), Firebase Perf,
  CleverTap, MobileAds init, `StartTimeProvider` (cold-start tracking)
- Permissions map to features: contacts+SMS (reminders), phone state/numbers
  (Truecaller auto-fill), camera (KYC/invoice scan), location (business seal),
  notifications (reminders), Bluetooth (thermal `printer` module), biometric
  (AppLock), SMS-receive (OTP auto-read)

## 7. Offline-first evidence

- `SyncableEntity`, `OneWaySyncableDto` / `TwoWaySyncableDto`, `BookVsServerSeq`
  (per-book server sequence numbers), Room (`core.database` provider,
  `ConfigDatabase`), WorkManager background sync, `backuprestore` module,
  `assets/dexopt/baseline.prof` (startup profiles)
- Invoices render **locally**: `assets/invoices/` has `invoice-1..4.html`,
  `thermal-template.html`, `premium-template.html`, `common.js`,
  `invoice-data-loader.js`, bundled fonts → shown in `bill_pdf_webview`
