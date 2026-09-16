# Oracle deploy bundle

> **Status: PARKED / on hold.** Render is the current (test) host — see
> `render.yaml` at the repo root and `docs/05` §0. These files stay in the
> repo for self-hosting later; do not provision Oracle right now.

Files for `docs/05-selfhost-deploy.md` — everything the VM needs:

| File | Purpose |
|---|---|
| `khata-backend-deploy.zip` (created next to this README) | Backend source **without** secrets, DBs, or `node_modules`. Upload to the VM. |
| `setup-oracle.sh` | One-shot provisioner: Node 22 + Caddy + deps + secrets + systemd + HTTPS. Usage is printed at the top of the script. |
| `khata.service` | systemd unit template (`__APP_USER__` / `__APP_DIR__` filled by the script). |
| `Caddyfile` | Reverse-proxy template (`__DOMAIN__` filled by the script). |

Order of work:

1. Oracle Cloud → Always-Free VM (Mumbai `ap-mumbai-1`), Ubuntu 24.04, open **80/443**.
2. DuckDNS hostname → VM public IP.
3. `scp` the zip up, `ssh` in, run `setup-oracle.sh <hostname>`.
4. Rebuild the APK with `--dart-define=API_BASE_URL=https://<hostname>`, install on both phones.
5. Same number + password on phone B → same books (sync test in `docs/05` §8).

Leaving Oracle later: copy `data/khata.db` + `.env` to your own server,
rerun `setup-oracle.sh`-equivalent steps there (or reuse these files) —
see `docs/05-selfhost-deploy.md` §10.
