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

Backend: ECR image (tagged with the commit SHA) → ECS Fargate behind an ALB with HTTPS, RDS
PostgreSQL, password in Secrets Manager. Frontend: static export in private S3 behind CloudFront.
Migrations run when the container starts.

No domain? Skip `API_DOMAIN`/`APP_DOMAIN`, `make cert-backend` and the `make cert`/`make domain` step. The API and
the site then both get HTTPS `*.cloudfront.net` addresses (the API through a CloudFront distribution in front of the load
balancer, so nothing needs a certificate).

One-time setup (your own AWS account, MFA on the root user, an IAM user, `aws configure` or SSO):

```bash
cp .env.example .env            # set AWS_REGION, API_DOMAIN=api.example.com, APP_DOMAIN=app.example.com
make cert-backend               # ACM certificate for the API (DNS-validated; Route 53 is automatic)
make deploy-backend             # image → ECR → ECS; prints the API URL and writes BACKEND_URL
make deploy-frontend            # builds against BACKEND_URL, syncs to S3, invalidates CloudFront
make cert DOMAIN=app.example.com && make domain DOMAIN=app.example.com   # frontend domain + HTTPS
make deploy-backend             # again: lets CORS allow the frontend domain
```

Keyless CI/CD: `make github-role` creates an OIDC role trusted only for `main` of your repo and sets
the repository variables. After that every push to `main` runs lint + tests, and if they pass,
deploys the backend and then the frontend (`.github/workflows/ci.yml`). Pull requests only check.

Rollback: `make rollback-backend IMAGE_TAG=<older commit sha>` (the image is still in ECR).
Logs: `make logs-backend`. Cost control: `make destroy-frontend destroy-backend` when you're done —
the RDS instance and the ALB bill by the hour.
