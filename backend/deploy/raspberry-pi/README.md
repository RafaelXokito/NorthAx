# Deploying the NorthAx backend on a Raspberry Pi (production)

Target: **Raspberry Pi OS / Debian (arm64)** — validated on **Debian 13 (Trixie),
Python 3.13, Pi 4/5**. The backend supports Python 3.11+. No Docker; runs
natively under systemd with Postgres + Redis from apt.

## One-time setup

Run `setup.sh` **as the login user** (e.g. `admin`) — not with `sudo`. It uses
`sudo` only for the root steps and creates the systemd services to run as that
same user.

```bash
# on the Pi, as the login user
git clone <repo-url> ~/northax          # private repo: use SSH agent forwarding (ssh -A) or a deploy key
bash ~/northax/backend/deploy/raspberry-pi/setup.sh
```

`setup.sh` installs packages; creates the `northax` DB role + database (tables
**owned by `northax`** so the app/jobs work as designed); applies `sql/schema.sql`;
builds the venv; **generates `ENCRYPTION_KEY` + JWT keys**; **auto-detects Hermes**
(`~/.local/bin/hermes`) and wires its absolute path; and starts the
`northax-api` + `northax-worker` services. Then fill `INTERVALS_*` +
`APPLE_CLIENT_ID` in `~/northax/backend/.env` and `sudo systemctl restart northax-api`.

```bash
curl -s http://localhost:8080/health          # {"status":"ok",...}
systemctl status northax-api northax-worker
journalctl -u northax-api -f                   # logs
~/northax/backend/.venv/bin/python -m app.seed # optional: seed athlete + initial sync
```

Reach it from the LAN at **`http://<pi-ip>:8080`** (e.g. `http://192.168.1.203:8080`);
point the iOS app's `NORTHAX_API_BASE_URL` at `http://<pi-ip>:8080/v1`.

## Does Hermes work on the Pi? — Yes ✅

Confirmed on this box: **Hermes Agent v0.15.1** at `~/.local/bin/hermes`
(provider `openai-codex`), auth healthy. `setup.sh` auto-wires `HERMES_CLI_PATH`
to its absolute path (systemd's PATH doesn't include `~/.local/bin`), so
`/readiness/today` returns a real AI narrative (~20 s cold, then cached; the
daily worker pre-warms it).

If Hermes is ever unavailable, the AI layer (isolated in `app/services/ai.py`)
falls back to deterministic-only. To use the Anthropic SDK instead:

```bash
.venv/bin/pip install '.[api]'
# set ANTHROPIC_API_KEY in .env, then point services/ai.py at the SDK
```

## Exposing it to the iOS app

On the same LAN, the app reaches the Pi over plain HTTP at `http://<pi-ip>:8080`
— the app's Info.plist sets `NSAllowsLocalNetworking` so ATS permits private-IP
HTTP. For remote/secure access, terminate TLS:

- **Tailscale** (simplest): `tailscale up` on the Pi + phone; use the Pi's
  `*.ts.net` name. HTTPS via Tailscale certs.
- **Caddy** reverse proxy with a domain + Let's Encrypt, proxying `:8080`.

## Notes / hardening

- **RLS**: the schema enables Row-Level Security, but a table *owner* bypasses
  it. For enforced RLS in prod, run the app as a non-owner role with `GRANT`s
  and add `FORCE ROW LEVEL SECURITY`. App-layer `WHERE user_id` is the primary
  isolation guard regardless.
- **Secrets**: `ENCRYPTION_KEY` lives in `.env` here; move to a secrets manager
  for a hardened setup (spec §5.8).
- **arm64 wheels**: `cryptography`, `asyncpg`, `pydantic-core` all ship arm64
  wheels; `build-essential`/`libpq-dev` are installed as a fallback.
