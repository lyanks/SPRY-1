# Lab 3 - the weekly meetings report (answers)

Code: `backend/app/reports/` (report + builder handler), `infra/reports.yaml` (queue, schedule,
S3 + endpoint, builder and mailer Lambdas), `scripts/reports.sh` (`make deploy-reports`,
`make report-now`). The report logic is a plain function and is tested without AWS
(`backend/tests/test_reports.py`).

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
Two. The builder is idempotent: both runs write the same key, `reports/2026-W40.csv`, so there is one file. But each
overwrite is a new `ObjectCreated` event, so the mailer runs twice and sends two emails. Writing a file twice is
harmless; sending an email twice is not, which is why question 1 needs its own "already sent" record.
(I derived this from the design; it has not been observed in a running account.)
