#!/usr/bin/env bash
# NorthAx backend — Raspberry Pi (Raspberry Pi OS / Debian Trixie, arm64) setup.
# Validated on a Pi 4/5 (Debian 13, Python 3.13). Run AS THE LOGIN USER (not with
# sudo) from anywhere; it uses sudo only for the root steps:
#
#   bash backend/deploy/raspberry-pi/setup.sh
#
# Result: Postgres + Redis, a venv, generated secrets, schema applied (tables
# owned by the app role), systemd services running as the login user, and the
# Hermes CLI auto-wired if present. Reach it on your LAN at http://<pi-ip>:8080.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_USER="$(whoami)"
DB_USER=northax
DB_NAME=northax
DB_PASS=${DB_PASS:-northax}
cd "$BACKEND_DIR"

echo "==> System packages (sudo)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql redis-server python3-venv python3-dev build-essential libpq-dev openssl

echo "==> PostgreSQL role + database (tables owned by '$DB_USER' so the app/jobs bypass RLS by design)"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS'"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
  || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
# pgcrypto needs superuser; the rest of the schema is applied AS the app role so
# it owns the tables (the CREATE EXTENSION line is stripped before that step).
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto" >/dev/null
grep -v 'CREATE EXTENSION' sql/schema.sql \
  | PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null
echo "    tables: $(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -tAc "select count(*) from pg_tables where schemaname='public'")"

echo "==> Python venv + deps (prefer wheels)"
python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install --prefer-binary -e .

echo "==> .env (generate secrets if missing)"
[ -f .env ] || cp .env.example .env
set_kv() { if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi; }
grep -q "^ENCRYPTION_KEY=.\+" .env || set_kv ENCRYPTION_KEY "$(openssl rand -hex 32)"
if ! grep -q "^JWT_PRIVATE_KEY=.\+" .env; then
  PRIV=$(openssl genrsa 2048 2>/dev/null); PUB=$(printf '%s' "$PRIV" | openssl rsa -pubout 2>/dev/null)
  set_kv JWT_PRIVATE_KEY "$(printf '%s' "$PRIV" | base64 -w0)"
  set_kv JWT_PUBLIC_KEY  "$(printf '%s' "$PUB"  | base64 -w0)"
fi
set_kv ENV production
set_kv DATABASE_URL "postgresql+asyncpg://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
set_kv REDIS_URL "redis://localhost:6379/0"
# Hermes auto-detect — absolute path, because systemd's PATH excludes ~/.local/bin.
HERMES_BIN=""
for c in "$HOME/.local/bin/hermes" "$(command -v hermes 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { HERMES_BIN="$c"; break; }
done
if [ -n "$HERMES_BIN" ]; then
  set_kv HERMES_CLI_PATH "$HERMES_BIN"; set_kv AI_CLI_FAST_TIMEOUT 90
  echo "    hermes wired: $HERMES_BIN"
else
  echo "    hermes not found — AI runs deterministic-only (or pip install '.[api]' + ANTHROPIC_API_KEY)"
fi
echo "    -> review $BACKEND_DIR/.env and fill INTERVALS_* + APPLE_CLIENT_ID"

echo "==> systemd services (User=$APP_USER)"
for unit in northax-api northax-worker; do
  sed -e "s|@BACKEND_DIR@|$BACKEND_DIR|g" -e "s|@APP_USER@|$APP_USER|g" \
    "deploy/raspberry-pi/$unit.service" | sudo tee "/etc/systemd/system/$unit.service" >/dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable --now northax-api northax-worker
sleep 3

echo "==> health: $(curl -s http://localhost:8080/health || echo FAIL)"
echo "==> api=$(systemctl is-active northax-api) worker=$(systemctl is-active northax-worker)"
echo "==> at home: http://$(hostname).local:8080  (the iOS app defaults to this)"
echo "==> away: reach over Tailscale's MagicDNS name; prefer 'tailscale serve' HTTPS (no ATS exception needed)"
echo "==> optional initial intervals.icu sync: .venv/bin/python -m app.seed"
