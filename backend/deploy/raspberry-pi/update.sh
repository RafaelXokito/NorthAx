#!/usr/bin/env bash
# NorthAx backend — Raspberry Pi update/deploy. Run AS THE LOGIN USER from
# anywhere (it uses sudo only to restart the services):
#
#   bash backend/deploy/raspberry-pi/update.sh
#
# Pulls origin/main, reinstalls deps only if pyproject changed, applies any
# pending sql/migrations/*.sql (each runs once, tracked in schema_migrations),
# restarts the systemd services, and checks /health. Set SMOKE_EMAIL +
# SMOKE_PASSWORD to also run a POST /auth/login smoke test.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$BACKEND_DIR/.." && pwd)"
VENV="$BACKEND_DIR/.venv"

echo "==> git pull --ff-only"
cd "$REPO_ROOT"
before="$(git rev-parse --short HEAD)"
git pull --ff-only
after="$(git rev-parse --short HEAD)"
if [ "$before" = "$after" ]; then echo "    already up to date ($after)"; else echo "    $before -> $after"; fi

cd "$BACKEND_DIR"

echo "==> dependencies"
if [ "$before" != "$after" ] && git diff --name-only "$before" "$after" | grep -q '^backend/pyproject.toml$'; then
  "$VENV/bin/pip" install -q --prefer-binary -e . && echo "    pyproject changed — deps reinstalled"
else
  echo "    pyproject unchanged — skipped"
fi

echo "==> migrations (sql/migrations/*.sql)"
"$VENV/bin/python" - <<'PY'
import asyncio, glob, os
import asyncpg
from app.config import settings

async def main():
    dsn = settings.database_url.replace("postgresql+asyncpg", "postgresql")
    conn = await asyncpg.connect(dsn)
    try:
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            "  filename TEXT PRIMARY KEY,"
            "  applied_at TIMESTAMPTZ NOT NULL DEFAULT now())")
        applied = {r["filename"] for r in await conn.fetch("SELECT filename FROM schema_migrations")}
        files = sorted(glob.glob("sql/migrations/*.sql"))
        pending = [f for f in files if os.path.basename(f) not in applied]
        if not pending:
            print("    no pending migrations")
            return
        for path in pending:
            name = os.path.basename(path)
            with open(path) as fh:
                sql = fh.read()
            async with conn.transaction():
                await conn.execute(sql)  # asyncpg simple-query runs multi-statement files
                await conn.execute("INSERT INTO schema_migrations(filename) VALUES($1)", name)
            print(f"    applied: {name}")
    finally:
        await conn.close()

asyncio.run(main())
PY

echo "==> restart services (sudo)"
sudo systemctl restart northax-api northax-worker
sleep 4
echo "    api=$(systemctl is-active northax-api) worker=$(systemctl is-active northax-worker)"

echo "==> health"
health="$(curl -s --max-time 10 http://localhost:8080/health || true)"
echo "    ${health:-FAIL}"
case "$health" in *'"status":"ok"'*) : ;; *) echo "    !! health check failed"; exit 1 ;; esac

if [ -n "${SMOKE_EMAIL:-}" ] && [ -n "${SMOKE_PASSWORD:-}" ]; then
  echo "==> login smoke test ($SMOKE_EMAIL)"
  code="$(curl -s -o /tmp/nx_smoke.json -w '%{http_code}' --max-time 10 \
    -X POST http://localhost:8080/v1/auth/login -H 'Content-Type: application/json' \
    -d "{\"email\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}")"
  if grep -q accessToken /tmp/nx_smoke.json 2>/dev/null; then
    echo "    HTTP $code — token pair OK"
  else
    echo "    HTTP $code — FAILED: $(cat /tmp/nx_smoke.json 2>/dev/null)"
    rm -f /tmp/nx_smoke.json; exit 1
  fi
  rm -f /tmp/nx_smoke.json
fi

echo "==> update complete ($after)"
