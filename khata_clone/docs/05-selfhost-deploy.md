# 05 — Online hosting + own-server migration

Goal: both phones sync anywhere over the internet. Laptop stays off.
Auth mode: **password** (zero SMS cost). OTP seam stays parked (see §6).

> ### Status
> **Render is the CURRENT host (testing).** The Oracle Always-Free track below
> (§1–§5, §9) is **commented out / on hold** — kept in the repo for when you
> want long-lived self-hosting without the Render free-tier limits. Do not run
> the commented steps unless you explicitly switch back.

## 0. CURRENT HOST — Render (free, for testing)

`render.yaml` at the repo root deploys the backend as a Render Web Service
(`khata-backend`, region Singapore, free plan). Ephemeral SQLite disk — data
resets when Render redeploys, and the service sleeps after ~15 min idle
(cold start ~30 s). Fine for a sync/password demo; not the durable home.

1. Push this repo to GitHub (branch `render-deploy`).
2. Render dashboard → **New + → Blueprint** (or Web Service) → connect the repo
   → pick branch **render-deploy** → `render.yaml` is auto-detected.
3. Render creates `JWT_SECRET` + `CIPHER_KEY` itself (`generateValue`).
4. Service URL becomes `https://<service>.onrender.com`. Check `/health`.

Point the app at it (one rebuild — or keep the LAN APK for local work):

```powershell
cd D:\khatabook\khata_clone\app
flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com
```

Secrets/account logic is identical to the Oracle path (§4, §6, §8). To leave
Render later, take `data/khata.db` + the two keys and follow §10.

<!-- Orcale track parked (see Status box). Sections 1–5, 7-Oracle-URL, 9. -->

## 1. Provision the free VM (one time, ~20 min of clicking)

1. Sign up at cloud.oracle.com (account + card verification; Always-Free tier costs ₹0).
2. Home region: **ap-mumbai-1 (Mumbai)** or ap-hyderabad-1 (keeps ledger data in India).
3. Create Compute instance: image **Ubuntu 24.04**, shape **Ampere A1** (or E2 micro),
   VCN with public subnet, **add SSH public key**, open ingress **80 + 443**
   (Security List; keep 22 open only to your IP).
4. Note the public IP, e.g. `203.0.113.10`.

## 2. Free hostname (TLS needs a name, not a bare IP)

1. Register e.g. `mykhata.duckdns.org` at duckdns.org → point to the VM IP.
2. On the VM, Caddy (step 4) fetches a Let's Encrypt certificate automatically.

## 3. Install runtime + code

```bash
ssh ubuntu@mykhata.duckdns.org
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs caddy
git clone <your-repo-url> khata && cd khata/backend
npm install --omit=dev
cp .env.example .env
```

## 4. Secrets (keys stay with YOU — never commit, never share)

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64'))"
# run twice → paste as JWT_SECRET and CIPHER_KEY (must differ, ≥32 chars)
```

`.env` on the server:

```
PORT=8080
DB_PATH=./data/khata.db
JWT_SECRET=<random-1>
CIPHER_KEY=<random-2>
AUTH_MODE=password
SEED_DEMO=0
# ALLOWED_ORIGINS= (native app sends no Origin; leave empty)
```

## 5. Run behind Caddy (auto-HTTPS, backend never touches the internet)

`/etc/caddy/Caddyfile`:

```
mykhata.duckdns.org {
    reverse_proxy 127.0.0.1:8080
}
```

```bash
sudo systemctl reload caddy
```

`/etc/systemd/system/khata.service`:

```
[Unit]
Description=Khata Clone backend
After=network.target
[Service]
WorkingDirectory=/home/ubuntu/khata/backend
ExecStart=/usr/bin/node src/index.js
Restart=always
EnvironmentFile=/home/ubuntu/khata/backend/.env
[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now khata
curl https://mykhata.duckdns.org/health  # {"ok":true,...}
```
-->

## 6. First account + lock the demo door

1. On phone A: open the app → enter number → **Create account** with a strong password → set profile + PIN.
2. SSH: verify `SEED_DEMO=0` took effect (no `9999999999` user):
   `node -e "const db=require('./src/db').migrate(require('./src/db').openDb()); console.log(db.prepare('SELECT phone FROM users').all())"`.
3. Confirm no `demo_code` ever appears in `/auth/*` responses (demo OTP is parked).

## 7. Point the app at the server (one rebuild)

```powershell
cd D:\khatabook\khata_clone\app
flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com  # Render (§0)
# Oracle track (parked): https://mykhata.duckdns.org
```

Install on phone A and B → log in with the **same number + password** → same books.
That is the account-based sync test (§8).

## 8. Two-phone sync test (do this before calling it done)

- [ ] Phone A (mobile data, laptop OFF): create customer + CREDIT entry.
- [ ] Phone B (different network): same login → entry visible.
- [ ] Wrong password → `invalid_credentials`, no hint whether the number exists.
- [ ] Staff invite → staff registers with own password → claim works, role gates hold.
- [ ] Logout on A → refresh revoked → old tokens 401.

<!-- Oracle-specific: daily snapshot + off-VM copy (parked with the Oracle track). -->
## 9. Backups (VM disk is not a backup)

Weekly cron on the VM:

```bash
sqlite3 /home/ubuntu/khata/backend/data/khata.db ".backup '/home/ubuntu/khata-backup/khata-$(date +%F).db'"
```

Copy the newest file off the VM monthly (scp to your laptop or encrypted USB).
App-level `GET /backup/export` remains the owner-only second copy.
-->

## 10. Migrating to YOUR OWN server later (exit door, ~15 min)

The backend is one Node app + one SQLite file; clients only know `API_BASE_URL`.

```bash
# on the Oracle VM
sqlite3 ~/khata/backend/data/khata.db ".backup '/tmp/khata.db'"
scp /tmp/khata.db you@own-server:/srv/khata/data/khata.db
scp ~/khata/backend/.env you@own-server:/srv/khata/.env   # same keys!
# on your own server: npm install --omit=dev, same systemd unit, point
# mykhata.duckdns.org (or your domain) DNS to it, Caddy as above
```

Then rebuild the APK only if the hostname changed. Recommended hardening
on own hardware: **no public ports** — phones connect via WireGuard VPN only,
disk encrypted (LUKS), same backup routine. No company holds the data.

## 11. Security checklist (viva-ready)

- [x] AES-256-GCM field encryption, `CIPHER_KEY` mandatory in production
- [x] 15-min JWT + rotating hashed refresh with reuse detection
- [x] Password bcrypt(10), generic `invalid_credentials`, login/register rate limits
- [x] CORS deny-by-default for browsers; helmet; zod validation
- [x] Staff RBAC (viewer/entry/manager) + audit log; owner-only backup
- [x] PIN/AppLock on every launch; demo OTP + demo account removed from prod
- [ ] Token storage → `flutter_secure_storage` (currently shared_preferences)
- [ ] Password-encrypted backup export (user passphrase) before any file sharing
- [ ] Offline write queue + `sync_seq` (concurrent A+B edits are last-write-wins today)

## 12. Reviving OTP later (when SMS is funded)

1. Uncomment: `require('../utils/otp')` + route block in `backend/src/routes/auth.js`.
2. Point `issueCode()`/sender seam in `backend/src/utils/otp.js` at the provider
   (Firebase Phone Auth / MSG91), set `ALLOW_DEMO_OTP=0`, remove `OTP_FIXED`.
3. Uncomment: `requestOtp/resendOtp/verifyOtp` in `app/lib/core/state.dart`,
   call sites in `otp_screen.dart`, route + import in `main.dart`.
4. Uncomment the parked block in `backend/tests/api.test.js`. `npm test` proves it.
