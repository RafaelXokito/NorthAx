#!/usr/bin/env bash
# NorthAx backend — Raspberry Pi (Raspberry Pi OS / Debian Bookworm) provisioning.
#
# Treats the Pi as the production server. Installs Postgres + Redis, a Python
# venv, generates secrets, applies the schema, installs systemd services, and
# reports whether the Hermes CLI is usable (the AI layer falls back to
# deterministic-only, or the Anthropic SDK, if it isn't).
#
# Usage (on the Pi, repo already cloned to $REPO_DIR):
#   sudo REPO_DIR=/opt/northax bash backend/deploy/raspberry-pi/setup.sh
set -euo pipefail

REPO_DIR=${REPO_DIR:-/opt/northax}
BACKEND_DIR="$REPO_DIR/backend"
DB_NAME=${DB_NAME:-northax}
DB_USER=${DB_USER:-northax}
DB_PASS=${DB_PASS:-northax}

echo "==> System packages"
apt-get update
apt-get install -y python3 python3-venv python3-dev build-essential \
  libpq-dev postgresql redis-server git curl openssl

echo "==> PostgreSQL: role + database"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
# Schema (creates pgcrypto, tables, RLS policies). Applied as superuser.
sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$BACKEND_DIR/sql/schema.sql"
# App connects as $DB_USER. NOTE: if you want RLS *enforced* (not just the
# app-layer WHERE user_id filter), make $DB_USER a non-owner with GRANTs and add
# FORCE ROW LEVEL SECURITY; by default a table owner bypasses RLS.

echo "==> Python venv + deps"
cd "$BACKEND_DIR"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .

echo "==> .env (generate secrets if missing)"
[ -f .env ] || cp .env.example .env
gen() { grep -q "^$1=.\+" .env && return 0 || return 1; }
set_kv() { local k="$1" v="$2"; if grep -q "^$k=" .env; then sed -i "s|^$k=.*|$k=$v|" .env; else echo "$k=$v" >> .env; fi; }
gen ENCRYPTION_KEY || set_kv ENCRYPTION_KEY "$(openssl rand -hex 32)"
if ! gen JWT_PRIVATE_KEY; then
  PRIV=$(openssl genrsa 2048 2>/dev/null); PUB=$(printf '%s' "$PRIV" | openssl rsa -pubout 2>/dev/null)
  set_kv JWT_PRIVATE_KEY "$(printf '%s' "$PRIV" | base64 -w0)"
  set_kv JWT_PUBLIC_KEY  "$(printf '%s' "$PUB"  | base64 -w0)"
fi
set_kv ENV production
set_kv DATABASE_URL "postgresql+asyncpg://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
set_kv REDIS_URL "redis://localhost:6379/0"
echo "    -> review $BACKEND_DIR/.env and fill INTERVALS_* + APPLE_CLIENT_ID"

echo "==> systemd services"
sed "s|@BACKEND_DIR@|$BACKEND_DIR|g" deploy/raspberry-pi/northax-api.service    > /etc/systemd/system/northax-api.service
sed "s|@BACKEND_DIR@|$BACKEND_DIR|g" deploy/raspberry-pi/northax-worker.service > /etc/systemd/system/northax-worker.service
systemctl daemon-reload
systemctl enable --now northax-api northax-worker

echo "==> Hermes CLI check (AI layer)"
if command -v hermes >/dev/null 2>&1; then
  echo "    hermes found: $(hermes --version 2>&1 | head -1)"
  echo "    smoke test:"; (hermes -z "reply with OK" 2>&1 | head -3) || echo "    hermes ran but errored (check 'hermes status' / auth)"
else
  echo "    hermes NOT installed on this Pi."
  echo "    AI explanations will be deterministic-only. To enable AI, either"
  echo "    install + authenticate hermes, OR: pip install '.[api]' and set"
  echo "    ANTHROPIC_API_KEY in .env (then flip services/ai.py to the SDK)."
fi

echo "==> Done. Health: curl -s http://localhost:8080/health"
echo "    Optional initial sync from env key: .venv/bin/python -m app.seed"
