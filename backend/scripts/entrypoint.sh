#!/usr/bin/env bash
set -euo pipefail

# On ECS and on Cloud Run the database settings arrive as separate variables (the
# password comes from Secrets Manager / Secret Manager). Build the URL here so the
# password never appears in a task definition. Locally, DATABASE_URL is simply set
# and this is skipped.
if [[ -z "${DATABASE_URL:-}" && -n "${DB_HOST:-}" ]]; then
  DATABASE_URL="$(python3 - <<'PY'
import os
from urllib.parse import quote

user = quote(os.environ.get("DB_USER", "spry"), safe="")
password = quote(os.environ["DB_PASSWORD"], safe="")
host = os.environ["DB_HOST"]
port = os.environ.get("DB_PORT", "5432")
name = os.environ.get("DB_NAME", "spry")
if host.startswith("/"):
    # Cloud Run: Cloud SQL is reached through a unix socket in this directory (/cloudsql/<connection name>).
    print(f"postgresql+asyncpg://{user}:{password}@/{name}?host={host}")
else:
    query = "?ssl=require" if os.environ.get("DB_SSL") == "require" else ""
    print(f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{name}{query}")
PY
)"
  export DATABASE_URL
fi

echo "[entrypoint] applying migrations..."
alembic upgrade head

# Cloud Run names the port in PORT (8080); ECS and Compose use 8000.
echo "[entrypoint] starting uvicorn..."
exec uvicorn app.main:app \
  --host 0.0.0.0 \
  --port "${PORT:-8000}" \
  --log-level "${LOG_LEVEL:-info}"
