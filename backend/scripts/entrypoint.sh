#!/usr/bin/env bash
set -euo pipefail

# On ECS the database settings arrive as separate variables (the password comes
# from Secrets Manager). Build the URL here so the password never appears in a
# task definition. Locally, DATABASE_URL is simply set and this is skipped.
if [[ -z "${DATABASE_URL:-}" && -n "${DB_HOST:-}" ]]; then
  DATABASE_URL="$(python3 - <<'PY'
import os
from urllib.parse import quote

user = quote(os.environ.get("DB_USER", "spry"), safe="")
password = quote(os.environ["DB_PASSWORD"], safe="")
host = os.environ["DB_HOST"]
port = os.environ.get("DB_PORT", "5432")
name = os.environ.get("DB_NAME", "spry")
query = "?ssl=require" if os.environ.get("DB_SSL") == "require" else ""
print(f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{name}{query}")
PY
)"
  export DATABASE_URL
fi

echo "[entrypoint] applying migrations..."
alembic upgrade head

echo "[entrypoint] starting uvicorn..."
exec uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --log-level "${LOG_LEVEL:-info}"
