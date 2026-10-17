# Lab 5 - the weekly meetings report

Commit: https://github.com/lyanks/SPRY-1/commit/11e198488bd487042ea59a3abc593f392eab5146
(branch `lab5`: the report code, the infrastructure template and the two Lambda handlers).

## Hand-in checklist

| # | Item | Where |
|---|------|-------|
| 1 | Link to the commit | the link above |
| 2 | Screenshot of the delivered email, CSV attached | attached to the submission |
| 3 | `aws s3 ls ... --recursive`, one report from the schedule and one from `make report-now` | section "Evidence" below |
| 4 | Three CloudWatch lines: `trigger=schedule`, `trigger=sqs`, `trigger=s3` | section "Evidence" below |
| 5 | Written answers to Step 7 | section "Step 7" below |

## What it does

Every Monday at 07:00 (Europe/Kyiv) the system builds a CSV report of last week's meetings, saves it
in S3 and emails it. Nobody clicks anything. Three triggers are involved:

```
EventBridge Scheduler / make report-now
   |  1. a schedule (or a person) puts a command on the queue
   v
SQS report-requests (+ dead-letter queue after 3 failures)
   |  2. an SQS message starts the builder
   v
Lambda report-builder (in the VPC) -- reads PostgreSQL --> writes reports/<week>.csv to S3
                                                            (through the free S3 gateway endpoint)
   |  3. the new file in S3 is an event
   v
Lambda report-mailer (outside the VPC) -- reads the file --> Amazon SES --> my inbox
```

- Code: `backend/app/reports/weekly.py` (a plain function, no AWS in it, tested in
  `backend/tests/test_reports.py`) and `backend/app/reports/lambda_handler.py` (the builder handler).
- Infrastructure: `infra/reports.yaml` (queue, dead-letter queue, schedule, bucket with a 90-day rule,
  S3 endpoint, both Lambdas, the S3 notification and its permission). The mailer is written inline.
- Commands: `make deploy-reports`, `make report-now WEEK=2026-W40`, `make destroy-reports`
  (`scripts/reports.sh`).
- The report: meetings and hours in the week, the same for the week before and the change, and the five
  longest meetings. The week is a parameter, and the file name is always `reports/<week>.csv`, so
  building a week twice overwrites one file (idempotent).

### Where my setup differs from the assignment text

- Region **eu-north-1** instead of us-east-1 (the S3 endpoint uses the stack's own region).
- **RDS PostgreSQL** instead of Aurora Serverless v2 (no 15-second resume, but the 60-second timeout stays).
- SES sandbox: the sender and the recipient are **one verified email address** (`REPORT_EMAIL`), not a domain.
- Since Lab 4 every calendar is private to its owner, but the report is a team-wide one: it reads all
  meetings and is not tied to a user.

## Evidence

On-demand requests (`make report-now`), each answered by an SQS `MessageId`:

```
make report-now WEEK=2026-W39   MessageId 969997cb-bf19-4645-8fb3-6781d028cb81   (the week made to fail, see Step 7 test 3)
make report-now WEEK=2026-W40   MessageId b0c0ff3e-d338-4947-b676-f98a1c514f9b
```

The real output (items 3 and 4):

```
aws s3 ls s3://spry-reports-818566829750/reports/ --recursive
2026-10-17 20:26:28        374 reports/2026-W40.csv      <- built on demand (make report-now WEEK=2026-W40)
2026-10-17 20:40:25        232 reports/2026-W41.csv      <- built by the schedule (previous ISO week)
```

One line per trigger (times are UTC). The last two are the same chain for 2026-W40, `sqs` then `s3`:

```
builder, trigger=schedule:  2026-10-17T17:45:23.984Z  fb9ba60b-ed95-57cd-81cd-c5465bfd3c47  report-builder trigger=schedule week=2026-W41
builder, trigger=sqs:       2026-10-17T17:26:25.813Z  5b81121c-9d0e-5b84-b63c-71512ce0af74  report-builder trigger=sqs week=2026-W40
mailer,  trigger=s3:        2026-10-17T17:26:28.193Z  42a02970-aafa-41c1-8b9f-ad4c3b7a3360  report-mailer trigger=s3 bucket=spry-reports-818566829750 key=reports/2026-W40.csv
```

The schedule ran several times during the `rate(5 minutes)` test (for example at 17:36, 17:40 and 17:45), and every
run built the same file, so S3 holds one `2026-W41.csv`. The report for 2026-W40 has 2 meetings and 2.75 hours.

The commands that produce those lines:

```
aws logs filter-log-events --region eu-north-1 --log-group-name /aws/lambda/spry-report-builder --filter-pattern '"trigger=schedule"' --query 'events[].message' --output text
aws logs filter-log-events --region eu-north-1 --log-group-name /aws/lambda/spry-report-builder --filter-pattern '"trigger=sqs"' --query 'events[].message' --output text
aws logs filter-log-events --region eu-north-1 --log-group-name /aws/lambda/spry-report-mailer --filter-pattern '"trigger=s3"' --query 'events[].message' --output text
```

## Step 7 - written answers

**1. The mailer got the same `ObjectCreated` event twice and sent two emails. Where do you store "already sent", and what is the key?**
In a small table with a conditional write - DynamoDB `PutItem` with `attribute_not_exists(pk)`, or a row with a
unique constraint in the existing PostgreSQL database (not reachable from the mailer, which is outside the VPC, so
DynamoDB fits). The key is **recipient + report key + S3 object version/ETag**, for example
`you@x.com#reports/2026-W40.csv#<etag>`. The mailer writes the key first; if the write is rejected, the email was
already sent and it stops. Including the ETag means a *rebuilt* report with different content is sent again, while a
duplicate event for the same file is not. (Write-then-send can lose an email if the function dies in between;
send-then-write can duplicate one. For a weekly report a rare duplicate is the lesser harm.)

**2. The builder in the VPC cannot reach SES. Three fixes and their monthly cost.**
- *NAT gateway*: about $0.045/hour, roughly **$33/month per availability zone**, plus $0.045 per GB processed.
- *VPC interface endpoint for SES*: about $0.01/hour per AZ, roughly **$7/month per AZ** (about $15 for two), plus
  $0.01 per GB.
- *The split I built*: the builder stays in the VPC and writes to S3 through the free gateway endpoint; the mailer
  outside the VPC reaches SES. About **$0** of fixed cost (Lambda, SQS, S3 events are free at this volume).

With ten more emails a week I would keep the split: any fixed monthly fee is absurd for ten emails. With a million
emails the SES fee itself (about $0.10 per thousand, roughly $100) dominates, and a fixed $7-$33 is small, so the
choice would be made on simplicity and other needs (if more functions in the VPC need the internet, a NAT or
endpoint starts to pay). I would still keep the split because it also keeps the mailer away from the database.

**3. A presigned link that works for a week.**
A URL presigned with a Lambda role's credentials stops working when the temporary session ends. Options: presign
with a long-lived IAM user's keys (valid up to 7 days, but that is the kind of permanent key we avoid), put the
reports behind **CloudFront with signed URLs** (the expiry is set by the signer, not by a session), or - the option I
would choose - put a link in the email that points to a small endpoint of our own; when clicked, it checks the
person and **mints a fresh short-lived presigned URL** and redirects to it. The link in the email never expires on
its own and never exposes the bucket.

**4. Send the same week twice - how many emails?**
Two. The builder is idempotent: both runs write the same key, `reports/2026-W40.csv`, so there is one file in
S3. But each overwrite is a new `ObjectCreated` event, so the mailer runs twice and sends two emails. Writing a
file twice is harmless; sending an email twice is not, which is why question 1 needs its own "already sent"
record.

**Observed:** I requested 2026-W40 several times. The first two requests were at 12:11:02 and 12:12:26 UTC (builder
`trigger=sqs`), and the mailer started once after each of them (`trigger=s3` at 12:11:04 and 12:12:27), while S3
kept a single `reports/2026-W40.csv`. The same happened for 2026-W41: several scheduled builds, one file, and a
mailer run after each. So the number of emails equals the number of runs, not the number of files.

### Step 7 test results

- [x] **1. On demand.** `make report-now WEEK=2026-W40` gave a new object in S3, a builder log line with
  `trigger=sqs`, a mailer log line with `trigger=s3`, and an email in my inbox (screenshot in the hand-in).
- [x] **2. Schedule.** I set the schedule to `rate(5 minutes)` for one run, found the builder log line with
  `trigger=schedule`, and set it back to `cron(0 7 ? * MON *)`.
- [ ] **3. Dead-letter queue.** `FAIL_WEEK=2026-W39 make deploy-reports` makes the builder raise for that week
  only. After `make report-now WEEK=2026-W39` the message came back 3 times and then sat in
  `report-requests-dlq`. Note: <how long it took, what the queue showed>
  After deploying the fixed code (`FAIL_WEEK` empty) I used **Start DLQ redrive** in the SQS console and the
  report was built. Note: <what I saw>
- [x] **4. Same week twice.** See answer 4 above.

## How the tests were run

```
make deploy-reports                                   # normal deploy
make report-now WEEK=2026-W40                         # trigger=sqs, then trigger=s3 in the mailer log
SCHEDULE='rate(5 minutes)' make deploy-reports        # one scheduled run: trigger=schedule
SCHEDULE='cron(0 7 ? * MON *)' make deploy-reports    # set it back
FAIL_WEEK=2026-W39 make deploy-reports                # the builder raises for that week only
make report-now WEEK=2026-W39                         # 3 failed receives, then the message is in the DLQ
make deploy-reports                                   # fixed (FAIL_WEEK empty), then SQS console -> DLQ -> Start DLQ redrive
```
