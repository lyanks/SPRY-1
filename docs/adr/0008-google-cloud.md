# 0008 - Spry's core on Google Cloud (a second cloud)

Status: accepted (Lab 9)

## Context

Spry runs on AWS (ADRs 0001-0007). Lab 9 asks what it takes to run the same system on another cloud,
and what that costs. The core that makes the app usable is the **frontend, the API and the database**;
sign-in, the weekly report and the agenda parser stay on AWS for now.

## Decision

A `gcp/` Terraform configuration (own state: the HCP Terraform workspace `spry-gcp`, Local execution,
so no Google key is stored anywhere) and `scripts/gcp.sh` to run it. Service by service:

| Spry on AWS | On Google Cloud | Decision |
|---|---|---|
| S3 + CloudFront + WAF (static frontend) | Firebase Hosting | **Replace.** Free plan, CDN and certificate included; also rewrites `/api/**` to Cloud Run, so the browser sees one origin and there is no CORS. A Cloud Storage bucket alone has no HTTPS on a custom domain without a load balancer, which bills by the hour. Not in Terraform: created by the Firebase CLI in `scripts/gcp.sh frontend`. |
| Lambda + function URL (FastAPI) | Cloud Run | **Replace.** The same Docker image (`runtime` stage), no Lambda adapter. Scales to zero, `max_instance_count = 2`. |
| ECR | Artifact Registry | **Replace.** 0.5 GB free. |
| Aurora Serverless v2 (pauses) | Cloud SQL for PostgreSQL, `db-f1-micro`, 10 GB SSD | **Replace**, see the database decision below. |
| DynamoDB (not used) | Firestore | **Drop.** Not used in Spry. |
| Cognito user pool + Google | Identity Platform | **Keep on AWS.** Cognito stays the identity provider; moving it means re-registering the Google OAuth client, migrating users and rewriting the token check in `app/auth.py`. Stretch goal. |
| EventBridge Scheduler (weekly report) | Cloud Scheduler | **Keep on AWS.** The report builder lives in a VPC next to the database it reads (Lab 5). |
| SQS | Pub/Sub or Cloud Tasks | **Drop.** Only the weekly report uses it, and the report stays. |
| S3 event -> Lambda | Cloud Storage + Eventarc | **Drop.** Same reason. |
| SES | no Google service | **Keep SES.** A multicloud architecture is allowed, and the report is the only thing that sends mail. If it moved: a provider such as Brevo or SendGrid, its API key in Secret Manager and read by the service account of the sender, never in an environment variable. |
| Bedrock (Claude Haiku 4.5) | Vertex AI (Gemini; Claude through Model Garden) | **Keep on AWS.** The parser is tuned and measured on Claude Haiku 4.5 with prompt `agenda-v1` (ADR 0006). The trial credit does not pay for partner models such as Claude. Comparing it with Gemini is a stretch. |
| Secrets Manager / SSM | Secret Manager | **Replace** for what moved: the database password. 6 active versions free. |
| CloudWatch Logs | Cloud Logging | **Replace** for what moved (Cloud Run logs there by itself). |
| IAM roles | Service accounts + IAM roles | **Replace.** `spry-api` (what the API runs as: `roles/cloudsql.client` on the project and `secretAccessor` on one secret) and `spry-terraform` (the CI deployer, reached only through Workload Identity Federation). Not the default compute account, and no Owner or Editor. |
| Terraform `aws` provider | Terraform `google` provider | **Add**, in its own folder and its own state. |

### The database

| Option | Latency | Bill (nobody using it) | Code |
|---|---|---|---|
| **Cloud SQL, stopped when not needed** | API to database in one region | about $1.70 (the disk bills while stopped), about $9.40 running | none: the same PostgreSQL, the same Alembic migrations, only the URL changes |
| Cloud SQL around the clock | same | about $9.40 | none |
| Firestore | none to speak of | $0 (free quota resets every day) | **rewritten**: documents instead of tables, no joins, the data layer and migrations replaced |
| Keep the database on AWS, call it from Cloud Run | about 100-150 ms per query between us-central1 and eu-north-1; a page with several queries feels it | Aurora's own bill, plus data transfer out of AWS, plus a public or VPN path into a VPC | none, but Aurora must be reachable from the internet |

**Chosen: Cloud SQL `db-f1-micro`, and the `db_running` variable of `gcp/` is the switch that stops it**
(`bash scripts/gcp.sh db-stop`). Firestore would be $0 but is a rewrite of every query and the loss
of the migrations and relations Spry already has; cross-cloud calls add latency and an exposed database
for no saving. The accepted risk: **Cloud SQL does not pause by itself**, so a forgotten instance bills
$9.40 a month forever. The mitigations are the budget alert (alerts only, it does not stop anything),
`db-stop`, and `terraform destroy` after grading.

### Connecting them

Cloud Run reaches Cloud SQL through the Cloud SQL connector: a unix socket mounted at `/cloudsql`,
authorised by the service account's IAM role. The instance's public address has no authorized network, so
nothing else can connect. The container's entrypoint builds `DATABASE_URL` from `DB_HOST`, `DB_USER`,
`DB_NAME` and `DB_PASSWORD` (the password arrives from Secret Manager as an environment variable that is
never in the repository); a `DB_HOST` that starts with `/` selects the socket form. Pooling is off
(`DB_POOLING=false`, one connection per request): a `db-f1-micro` allows few connections and instances come and go.

The browser talks to `https://<project>.web.app` only. Firebase Hosting serves the static export and
rewrites `/api/**` and `/health/**` to Cloud Run, so the bundle is compiled with an empty API URL and
no CORS is involved. CORS still lists the two Hosting origins for direct calls.

## Alternatives

- **Cloud Storage bucket + load balancer for the frontend.** Works, but the load balancer bills by the hour.
- **Cloud Run for the frontend too (the standalone image).** One more always-possible cold start for something that is static files.
- **AlloyDB.** Aurora-like, far larger than a class project needs.
- **Terraform state in a GCS bucket.** Needs a bucket bootstrapped by hand; HCP Terraform already holds the other state.

## Consequences

- **The API is open in this lab.** With sign-in still on AWS, the API runs with `APP_ENV=development`:
  one shared demo user, so anyone who has the URL can read and write the demo data. The data is
  demo data, instances are capped at 2, and everything is destroyed after grading. To close it: put the
  Firebase Hosting URL into the Cognito app client's callback URLs (a change to `infra/auth.tf`, applied
  through HCP Terraform), set `app_env = "production"` and the three `cognito_*` variables, and build the
  frontend with the Cognito variables. The API then checks the access token on every request, exactly as on AWS.
- **State.** The database password is in the Terraform state (and in Secret Manager). The state is in HCP
  Terraform, limited to the organization's members.
- **No long-lived keys.** Terraform runs with the developer's own credentials locally and with Workload
  Identity Federation in CI (`gcp/ci.tf`: a pool, a GitHub provider whose attribute condition admits only this
  repository by its numeric ID, and `workloadIdentityUser` on one service account).
- **Cost.** See LAB9.md: cheaper than AWS for office-hours and always-on use (an instance at $0.0105 an hour
  against Aurora's 0.5 ACU floor at $0.06), dearer when nobody is using it (the disk bills while stopped,
  Aurora pauses).
- **Lock-in.** The container, the SQL and Alembic moved unchanged. What did not move: the Firebase CLI step,
  the `cloudsql` socket URL, and the IAM model. The lock-in is in the managed services around the compute,
  not in the compute.
