# Lab 9: one project, two clouds

Spry's core (frontend, API, database) runs on Google Cloud. Sign-in, the weekly report and the agenda
parser stay on AWS. The decisions are in [docs/adr/0008-google-cloud.md](docs/adr/0008-google-cloud.md);
the Terraform is in [gcp/](gcp/); everything is driven by `scripts/gcp.sh`.

| Submission item | Where |
|---|---|
| 1. Commit with `gcp/` and the ADR | the pull request of branch `lab9` (link in the LMS) |
| 2. URL of the project on Google Cloud | `https://<project-id>.web.app` (the line printed by `scripts/gcp.sh smoke`) |
| 3. Cost table | below |
| 4. Three demo screenshots | Part 4 below: BigQuery, Looker Studio, Vision OCR |

## What runs where

```
browser -> Firebase Hosting (static Next.js export, CDN, HTTPS)
              | rewrites /api/**, /health/** to
              v
           Cloud Run  spry-api  (the backend image, scales to zero, runs as service account spry-api)
              | Cloud SQL connector (unix socket, IAM)        | secret
              v                                               v
           Cloud SQL PostgreSQL 16 (db-f1-micro, 10 GB)    Secret Manager: spry-db-password

still on AWS: Cognito (sign-in), the weekly report (Lambda, SES, S3), the agenda parser (Lambda, Bedrock)
```

Migrations: the container runs `alembic upgrade head` on start, as on AWS, so the empty Cloud SQL
database gets its schema the first time the API starts. No data was copied from Aurora (the migrations
were run against the empty database); the demo rows are created through the API by `scripts/gcp.sh smoke`.

## Part 3: the cost table

Prices: the list prices of the lab text (checked 5 November 2026), us-central1 for Google Cloud, us-east-1
for AWS, 730 hours a month, no tax.

### Spry's core, nobody using it for a month

| Piece | AWS (Lab 4, Stage 2) | Google Cloud (this project) |
|---|---|---|
| Frontend + CDN + HTTPS | CloudFront Free plan: **$0** | Firebase Hosting free plan: **$0** |
| API | Lambda, idle: **$0** | Cloud Run, scaled to zero: **$0** |
| Database compute | Aurora paused: **$0** | Cloud SQL `db-f1-micro` **stopped**: **$0** (running: $0.0105/h = **$7.67**) |
| Database storage | about 1 GB x $0.10: **$0.10** | 10 GB SSD x $0.17: **$1.70** (billed while stopped) |
| Registry, secrets, logs | a few cents | within the free tier (Artifact Registry 0.5 GB, 6 secret versions) |
| **Total** | **about $0.30 / month** | **about $1.70** stopped, **about $9.40** running |

Free-tier assumptions: Cloud Run 2M requests, 180,000 vCPU-seconds and 360,000 GiB-seconds a month;
Firebase Hosting 10 GB stored and 360 MB a day out; Secret Manager 6 active versions; Artifact Registry
0.5 GB (one image of about 250 MB). With Firestore instead of Cloud SQL the same row would be **$0**
(50,000 reads, 20,000 writes a day free), at the price of rewriting the data layer; I did not choose it (ADR 0008).

### The four traffic profiles (a month)

Assumptions: the AWS database awake is billed at Aurora Serverless v2's **0.5 ACU floor** ($0.12 per
ACU-hour, so $0.06 an hour) on top of the $0.30 idle bill; "busy" means one request a second for 730 hours
(2.6 million requests, 0.1 s of CPU each); the Cloud SQL instance is **stopped outside the hours the profile
uses it** (`db-stop`), or left running in the last column. AWS numbers are rebuilt from list prices because
the Lab 4 table is not in this repository; replace them with your own Lab 4 figures if they differ.

| Profile | Hours the DB is on | AWS | GCP, Cloud SQL stopped when idle | GCP, Cloud SQL left running | GCP with Firestore |
|---|---|---|---|---|---|
| Nobody | 0 | **$0.30** | $1.70 | $9.37 | **$0** |
| Class demos (10 x 2 h) | 20 | $1.50 | $1.91 | $9.37 | $0 |
| Office hours (8 h x 22 days) | 176 | $10.86 | **$3.55** | $9.37 | $0 |
| Busy, around the clock | 730 | $44.42 | **$11.53** | $11.53 | $3.27 |

How the cells were computed: AWS = $0.30 + hours x $0.06 + Lambda requests above the free million at
$0.20 per million. GCP = $1.70 disk + hours x $0.0105 + Cloud Run (requests above 2M at $0.40 per million,
CPU-seconds above 180,000 at $0.000024). Firestore = Cloud Run + document reads above 50,000 a day (2 reads
per request) at $0.03 per 100,000. Check each cell in the Google Cloud and AWS pricing calculators before
you hand it in; I could not run them from here, and both clouds may have added or removed lines (for example
the public IPv4 address of the Cloud SQL instance).

### Which cloud is cheaper, and which line decides it?

- **Nobody:** AWS ($0.30 against $1.70, or $0 with Firestore). The deciding line is **database
  storage while idle**: Aurora's compute pauses and its 1 GB is $0.10, while Cloud SQL's 10 GB disk bills
  $1.70 even when the instance is stopped.
- **Class demos:** about equal (AWS $1.50, GCP $1.91). Aurora's pausing cancels the cheaper instance.
- **Office hours and busy:** Google Cloud, by a lot ($3.55 against $10.86; $11.53 against $44.42). The deciding line
  is the **hourly price of the database being awake**: Aurora Serverless v2 never goes below 0.5 ACU = $0.06 an
  hour, and `db-f1-micro` is $0.0105, six times less. Serverless is cheaper only while it is asleep.

### Where is the GCP trap?

Lab 4's trap was Aurora costing more than an instance because something kept it awake. The mirror image
on Google Cloud is that **Cloud SQL never pauses by itself**: forget it and it is $9.37 a month for an empty
database, which is more than AWS for nobody, demos and (almost) office hours. The second trap is that **stopping
it does not stop the disk** ($1.70 a month). Defences: the $5 budget alert (it only sends e-mails, it does not stop spending), the
`db_running` variable, and `terraform destroy` when you are done. Firestore has no such trap, but a list page that
reads 500 documents per visit spends the 50,000 free reads a day after 100 visits.

## Part 4: the three demos

Do these in the Google Cloud console and Looker Studio, signed in with the same account.

1. **BigQuery** (the sandbox needs no card): open https://console.cloud.google.com/bigquery and run

   ```sql
   SELECT word, SUM(word_count) AS total
   FROM `bigquery-public-data.samples.shakespeare`
   GROUP BY word
   ORDER BY total DESC
   LIMIT 10
   ```

   Screenshot the result with the query text and the **bytes processed** line (the query-results panel, "Job information",
   or the green tick above the editor). Write the number down: the lab asks for it, and BigQuery bills by it
   (first 1 TiB a month free, then $6.25 per TiB).
2. **Looker Studio**: in the results click *Explore data* -> *Explore with Looker Studio*, choose a bar chart with
   `word` as the dimension and `total` as the metric. Screenshot the chart.
3. **Vision OCR**: the drag-and-drop demo at https://cloud.google.com/vision/docs/drag-and-drop needs no project;
   drop a photo of a receipt or a handwritten page and screenshot the *Text* tab with the recognised text.
   (Document AI works too: create an *Enterprise Document OCR* processor in the console and upload a PDF; the first
   1,000 pages a month are free.)

### Questions of Part 4

**When is Document AI better than a general model, and when is it not?** A specialised processor wins when the
documents are many and look alike (invoices, receipts, forms, scanned contracts): it is cheaper per page and
priced per page ($1.50 per 1,000 pages for OCR, $30 per 1,000 for the Form Parser), it returns the position of each
word and a confidence score, its output is stable from run to run, and it handles scans and handwriting. A general
model wins when the input is varied or has to be interpreted, not only read: Lab 6 turned free text into a
schema of agenda items, which needs judgement and an output schema of my choosing, and the input was already
text. The two combine: OCR with Document AI or Vision first, then an LLM for the meaning, which is what a photographed
handwritten agenda would need.

**Lab 8 on Google Cloud.** S3 -> Cloud Storage; Athena -> **BigQuery** (an external table over the files, or the data loaded
into BigQuery's own storage); the Glue Crawler and Glue jobs -> **Dataflow** (the *Cloud Storage Text to BigQuery* template reads
the JSON Lines and writes a table; the schema is given by me or by BigQuery's autodetect); Kinesis + Firehose ->
Pub/Sub (+ Dataflow, or a BigQuery subscription); QuickSight -> **Looker Studio**; the nightly orchestration -> Cloud Composer
(managed Airflow). What I would no longer manage: the CTAS to Parquet and the `dt` partition folders (BigQuery stores
data in its own columnar format and partitions or clusters the table itself, so "1,202 MB against 6 MB" becomes a partitioned
table choice and a `SELECT` of only the columns needed), `MSCK REPAIR TABLE`, the Athena results bucket, and the cluster
(there is none). What I would still own: the schema, the partitioning choice, the cost of each query (it bills by bytes
scanned, like Athena), and the access control.

**Veo.** An 8-second clip costs about $0.40 (Veo 3.1 Lite, 720p, $0.05 a second) up to $3.20 (Veo 3.1 with audio, $0.40 a
second): a hundred such clips a month is $320, which is why it is a class demo and not a student task.

## Part 5: certifications

Nothing to hand in. The matches for this project: **Associate Cloud Engineer** (Parts 0-2 are what it tests),
**Associate Data Practitioner** (Part 4 and Lab 8) and **Professional Cloud Architect** (the closest to the course).
A certification outside the course Bonus list needs the lecturer's written approval before the exam.

## How to run it (the order)

One-time, by hand (an account, a card for the free trial and a login are yours to do):

1. Google Cloud **Free Trial** ($300 for 90 days, not billed during the trial). *Billing -> Budgets & alerts ->
   Create budget*: $5 a month, 50/90/100%. (An alerts-only budget e-mails; it does not stop spending.)
2. Create the project, with an ID like `spry-yourname-2026`, and link the trial billing account to it.
3. `gcloud auth login` and `gcloud auth application-default login`, then `gcloud config set project <id>`.
4. HCP Terraform: workspace `spry-gcp` in your organization, **Execution Mode = Local**; `terraform login` if the token is gone.
5. `GCP_PROJECT_ID=<id>` in `.env` (see `.env.example`).
6. `npx firebase-tools@14 login` (the Firebase CLI deploys the site).

Then:

```bash
bash scripts/gcp.sh check
bash scripts/gcp.sh up        # bootstrap + image + apply + frontend + smoke   (about 15 minutes, most of it Cloud SQL)
```

or one phase at a time (`bootstrap`, `image`, `apply`, `frontend`, `smoke`).

## Clean up

```bash
bash scripts/gcp.sh db-stop    # keep the project, stop the instance billing compute
bash scripts/gcp.sh destroy    # delete everything this lab created (type the project ID)
```

Then in the Firebase CLI: `npx firebase-tools@14 hosting:disable --project <id>`, delete the BigQuery tables
you made, and look at *Billing -> Reports* a day later. A Cloud SQL instance left running is the most common
surprise on a student's bill.

## For the class

- **Lock-in:** the container, the SQL and the migrations moved unchanged. What did not: the IAM model, the way the
  database is reached (a unix socket, not a security group), the static-site hosting and its CLI. The lock-in is in the
  managed services around the compute, not in the compute.
- **Multicloud:** this is a migration state, not a design. Sign-in on AWS and the API on Google cost a cross-cloud call
  (the API fetches Cognito's public keys once and caches them, so it is small), egress, two consoles, two budgets, two
  sets of credentials. It is justified only when one cloud has something the other has not (here: nothing yet).
- **Scale to zero:** Aurora pauses, Cloud SQL does not, Firestore has nothing to pause. Giving up SQL to save about $9
  a month is a bad trade for Spry (relations, migrations, a rewritten data layer), and a good one for a table of a few
  independent documents.
- **Choosing a cloud:** at this size the price difference is a few dollars; credits, the AI and data services, and what
  the team already knows decide.
