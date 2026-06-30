# Deploying the NorthAx backend on a Raspberry Pi (production)

Target: **Raspberry Pi OS / Debian Bookworm (arm64)**. Python 3.11 (Bookworm
default) — the backend supports 3.11+. No Docker needed; runs natively under
systemd with Postgres + Redis from apt.

## One-time setup

```bash
# on the Pi
sudo mkdir -p /opt/northax && sudo chown "$USER" /opt/northax
git clone <repo-url> /opt/northax
# create the service user the units run as
sudo useradd --system --home /opt/northax northax || true
sudo chown -R northax /opt/northax
sudo REPO_DIR=/opt/northax bash /opt/northax/backend/deploy/raspberry-pi/setup.sh
```

`setup.sh` installs packages, creates the DB + role, applies `sql/schema.sql`,
builds the venv, **generates `ENCRYPTION_KEY` + JWT keys**, installs and starts
the `northax-api` and `northax-worker` systemd services, and reports the Hermes
status. Then edit `/opt/northax/backend/.env` to fill `INTERVALS_*` and
`APPLE_CLIENT_ID`, and `sudo systemctl restart northax-api`.

```bash
curl -s http://localhost:8080/health          # {"status":"ok",...}
sudo systemctl status northax-api northax-worker
journalctl -u northax-api -f                   # logs
# optional: seed your athlete + initial sync from INTERVALS_API_KEY
sudo -u northax /opt/northax/backend/.venv/bin/python -m app.seed
```

## Does Hermes work on the Pi?

This is the open question the deploy answers at run time. `setup.sh` prints one of:

- **`hermes found` + a working smoke test** → AI is live on the Pi.
- **`hermes found` but errors** (e.g. the `Codex token refresh failed` we saw on
  the Mac) → re-authenticate on the Pi (`hermes status`, `hermes login`).
- **`hermes NOT installed`** → most likely on a fresh Pi. Hermes ships as a
  CLI; whether the installer supports arm64 Linux must be confirmed on the box.

**Fallback if Hermes can't run on the Pi:** the AI layer is isolated in
`app/services/ai.py`. Install the Anthropic SDK and use it instead:

```bash
.venv/bin/pip install '.[api]'
# set ANTHROPIC_API_KEY in .env, then point services/ai.py at the SDK
```

Either way the app stays functional — without a working AI provider it returns
the deterministic readiness/coach results, just without the AI narrative.

## Exposing it to the iOS app (TLS)

iOS App Transport Security blocks plain HTTP. For on-device use, terminate TLS:

- **Tailscale** (simplest): `tailscale up` on the Pi and the phone; use the
  Pi's `*.ts.net` name as `NORTHAX_API_BASE_URL`. HTTPS via Tailscale certs.
- **Caddy** reverse proxy with a real domain + Let's Encrypt, proxying `:8080`.

## Notes / hardening

- **RLS**: the schema enables Row-Level Security, but a table *owner* bypasses
  it. For enforced RLS in prod, run the app as a non-owner role with `GRANT`s
  and add `FORCE ROW LEVEL SECURITY`. App-layer `WHERE user_id` is the primary
  isolation guard regardless.
- **Secrets**: `ENCRYPTION_KEY` lives in `.env` here; move to a secrets manager
  for a hardened setup (spec §5.8).
- **arm64 wheels**: `cryptography`, `asyncpg`, `pydantic-core` all ship arm64
  wheels; `build-essential`/`libpq-dev` are installed as a fallback.
