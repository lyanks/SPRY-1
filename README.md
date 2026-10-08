# Spry

Meeting analytics: weekly meeting load, deep-work slots and agenda readiness.
FastAPI + PostgreSQL backend, Next.js + shadcn/ui frontend, one monorepo.
The API contract and data model are in [PROJECT.md](PROJECT.md).

## Run it

```bash
cp .env.example .env
docker compose up --build
```

| URL | What |
|---|---|
| http://localhost:3000 | Frontend |
| http://localhost:8000/docs | API docs (Swagger) |
| http://localhost:8000/health | Liveness |

The backend applies Alembic migrations on start, after Postgres reports healthy.

## Backend without Docker

```bash
docker compose up -d db
cd backend && uv sync
DATABASE_URL=postgresql+asyncpg://spry:spry@localhost:5432/spry uv run alembic upgrade head
DATABASE_URL=postgresql+asyncpg://spry:spry@localhost:5432/spry uv run uvicorn app.main:app --reload
```

## Tests and lint

```bash
cd frontend && pnpm test && pnpm lint
cd backend && DATABASE_URL=postgresql+asyncpg://spry:spry@localhost:5432/spry uv run pytest
cd backend && uv run ruff check . && uv run ruff format --check .
```

Tests use a real PostgreSQL. The suite derives `<database>_test` from `DATABASE_URL`, drops and
recreates its schema there, so never point it at data you care about.

## Deploy to AWS

`make deploy-backend`, `make deploy-frontend`, `make domain DOMAIN=app.example.com`.
`make github-role` sets up keyless deploys from GitHub Actions: put the word `deploy` in a commit
message on `main`. The scripts and CloudFormation templates are in `scripts/` and `infra/`.
