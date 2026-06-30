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

## Updating (redeploy)

After the one-time setup, pull and roll out new code with one command, run **as
the login user** on the Pi:

```bash
bash ~/northax/backend/deploy/raspberry-pi/update.sh
```

It does `git pull --ff-only`, reinstalls deps only if `pyproject.toml` changed,
applies any pending `sql/migrations/*.sql` (each runs once, tracked in a
`schema_migrations` table), restarts both services, and verifies `/health`.
Add an optional login smoke test with env vars:

```bash
SMOKE_EMAIL=dev@northax.app SMOKE_PASSWORD=northax-dev \
  bash ~/northax/backend/deploy/raspberry-pi/update.sh
```

**Schema changes** ship as a new idempotent file under `backend/sql/migrations/`
(e.g. `0002_*.sql`) — `update.sh` applies it on the next deploy. `schema.sql`
stays the full current schema for fresh installs.

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

The app defaults (DEBUG) to the mDNS domain **`http://rafaelpereira.local:8080`**,
which works at home; its Info.plist sets `NSAllowsLocalNetworking` so ATS allows
`.local` over HTTP.

> **mDNS must be IPv4-only.** The API binds IPv4 (`uvicorn --host 0.0.0.0`;
> `--host ::` is IPv6-only here, not dual-stack). If avahi advertises the Pi's
> global IPv6 (AAAA), iOS will prefer it and every request gets a TCP RST. Set
> `use-ipv6=no` under `[server]` in `/etc/avahi/avahi-daemon.conf` and
> `sudo systemctl restart avahi-daemon` so `rafaelpereira.local` resolves to
> IPv4 only.

**Away from home — Tailscale (the plan):** put the Pi and the iPhone on the same
tailnet (`tailscale up`). Then reach the Pi by its MagicDNS name from anywhere:

- **Preferred — HTTPS, no ATS exception:** `tailscale serve` issues a real
  `*.ts.net` cert. e.g. `sudo tailscale serve --bg 8080`, then set the app's
  `NORTHAX_API_BASE_URL=https://rafaelpereira.<tailnet>.ts.net/v1`.
- Plain HTTP over the tailnet works too, but the `100.x`/`ts.net` host isn't
  "local", so it needs an `NSExceptionDomains` entry (or use the HTTPS option).

Because MagicDNS resolves the same name at home and away, a single
`https://…ts.net/v1` URL can serve both once Tailscale is always-on on the phone.

## Notes / hardening

- **RLS**: the schema enables Row-Level Security, but a table *owner* bypasses
  it. For enforced RLS in prod, run the app as a non-owner role with `GRANT`s
  and add `FORCE ROW LEVEL SECURITY`. App-layer `WHERE user_id` is the primary
  isolation guard regardless.
- **Secrets**: `ENCRYPTION_KEY` lives in `.env` here; move to a secrets manager
  for a hardened setup (spec §5.8).
- **arm64 wheels**: `cryptography`, `asyncpg`, `pydantic-core` all ship arm64
  wheels; `build-essential`/`libpq-dev` are installed as a fallback.
