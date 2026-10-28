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

## Infrastructure as code (Lab 7)

The Cognito pool (Lab 4), the weekly report (Lab 5) and the agenda parser (Lab 6) are
Terraform in `infra/`: `auth.tf`, `reports.tf`, `ai.tf`, with `variables.tf`, `outputs.tf`
and `versions.tf`. (The backend, database and site of the course template are still
CloudFormation: `backend.yaml`, `frontend.yaml`, `github-oidc.yaml`.) The state lives in
the HCP Terraform workspace `spry-dev`; **nothing applies from a laptop**.

| I want to | Do |
|---|---|
| change infrastructure | edit `infra/*.tf`, open a pull request, read the plan in the check, merge: HCP Terraform applies |
| see what would change | `make infra-plan` (read-only) |
| check syntax | `make infra-fmt infra-validate` |
| read a value | `make infra-output` or `terraform -chdir=infra output -raw parser_url` |
| ship a new Lambda image | `make push-image`, then set `image_uri` in the workspace |

Variables: non-secret values are in `infra/terraform.tfvars`; `google_client_secret` is a
sensitive variable of the workspace. One-time setup: put your HCP organization's name in `infra/versions.tf`, run `terraform login`, then `make infra-init`.
CI (`.github/workflows/ci.yml`) cannot read Terraform outputs without a token, so `make deploy-frontend` and
`make deploy-backend` also accept `COGNITO_AUTHORITY`, `COGNITO_CLIENT_ID`, `COGNITO_DOMAIN`, `PARSER_URL`,
`COGNITO_USER_POOL_ID` from the environment (set them as repository variables).
Decision record: `docs/adr/0007-terraform.md`.

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
   - Set the client ID as `google_client_id` and the secret as the **sensitive** variable
     `google_client_secret` in the HCP Terraform workspace (see "Infrastructure" below).
2. The user pool, Google provider, public app client, domain and managed-login branding are
   `infra/auth.tf`. After the workspace applies, `make deploy-frontend` reads the Terraform
   outputs and compiles them into the build.
3. `make deploy-backend` once more: it reads the same outputs and tells the API which
   Cognito pool and app client to trust. Until then the API answers calendar requests
   with 401/503 - it fails closed.
4. Open `<site>/login/`. Try it in a private window, once with an email and password
   (Cognito mails a confirmation code) and once with **Continue with Google**.

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

