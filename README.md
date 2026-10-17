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

Keyless CI/CD: `make github-role` creates an OIDC role trusted only for your deploy branch (`main` or `master`, whichever you push to) and sets
the repository variables. After that every push to `main`/`master` runs lint + tests, and if they pass,
deploys the backend and then the frontend (`.github/workflows/ci.yml`). Pull requests only check.

Rollback: `make rollback-backend IMAGE_TAG=<older commit sha>` (the image is still in ECR).
Logs: `make logs-backend`. Cost control: `make destroy-frontend destroy-backend` when you're done —
the RDS instance and the ALB bill by the hour.

## Sign-in with Cognito (Lab 4)

People sign in with an email and a password or with Google. The browser talks
only to Amazon Cognito (managed login); Cognito talks to Google. The site is
still a static export: `react-oidc-context` starts the login at `/login/`,
Cognito returns the browser to `/auth/callback`, and the header shows the
signed-in email. Without the Cognito stack the site builds and runs as before.

1. **Google OAuth client** (Google Cloud console, a project of your own):
   - Google Auth Platform -> Branding / Audience: user type **External**, scopes
     `openid`, `email`, `profile` only, then **Publish app** (status "In production").
     In "Testing" only listed test users can sign in.
   - Clients -> Create client -> **Web application**. `make auth-uris` prints the
     two values it needs (they point at Cognito, not at the site).
   - Put the client ID and secret in `.env` as `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`.
2. `make deploy-frontend` (once, so the site's URL exists), then `make deploy-auth`
   (creates `infra/auth.yaml`: user pool, Google provider, public app client, domain,
   managed-login branding), then `make deploy-frontend` again - it reads the stack's
   outputs and compiles them into the build.
3. `make deploy-backend` once more: it reads the auth stack and tells the API which
   Cognito pool and app client to trust. Until then the API answers calendar requests
   with 401/503 - it fails closed.
4. Open `<site>/login/`. Try it in a private window, once with an email and password
   (Cognito mails a confirmation code) and once with **Continue with Google**.

`make destroy-auth` removes the stack and its users.

### Who sees what

- **Not signed in:** the front page is a landing page with a read-only *sample week*
  (made-up meetings built in the browser, nothing from the API). `/meetings` asks you
  to sign in. Nothing can be edited.
- **Signed in:** your own calendar. The API verifies the Cognito access token on every
  `/api/meetings`, `/api/insights`, `/api/agenda` and `/api/deep-work` call (signature,
  issuer, expiry, `token_use=access`, app client) and stores the token's `sub` as the
  meeting's `owner_id`. Every query filters on it, so another person's meeting is simply
  "not found" (404) - you cannot read, edit or delete it, and it never counts in your
  numbers or blocks your deep-work slots.
- `/health` stays public. The weekly report (Lab 3) still covers all meetings.
- Meetings created before accounts existed get `owner_id = 'unclaimed'` (migration 0004)
  and are shown to nobody.
- Local `docker compose up` has no Cognito: in development the API treats everyone as
  one `dev-user`, so the app works as before. In production, an API with no Cognito
  configured refuses requests (503).

