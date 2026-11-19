#!/usr/bin/env bash
# Lab 8, Part 2. Run the phases one at a time and look at each result:
#   bash lab8/part2.sh check      which services your account lets you use (S3, Athena, Glue, Kinesis, Firehose)
#   bash lab8/part2.sh setup      bucket in us-east-1 + copy of the dataset      (~1.2 GB, free inside a region)
#   bash lab8/part2.sh tables     Athena database, table, partitions, count      (query 1)
#   bash lab8/part2.sh queries    scale, dedup view, queries 3-6 on JSON         (queries 2-6)
#   bash lab8/part2.sh parquet    CTAS to Parquet, queries 3-5 again, comparison (query 7)
#   bash lab8/part2.sh crawler    Glue Crawler and its schema                    (Way B)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Your account's policy refuses S3 buckets in us-east-1, so everything lives in eu-north-1 (set
# LAB8_REGION to change it). The source bucket stays in us-east-1: copying across costs about 2 cents.
REGION="${LAB8_REGION:-eu-north-1}"
export AWS_REGION="${REGION}" AWS_DEFAULT_REGION="${REGION}"
[[ -n "${AWS_PROFILE:-}" ]] || unset AWS_PROFILE
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
export BUCKET="${BUCKET:-spry-lab8-${ACCOUNT}}"
SOURCE="s3://ucu-ooad-lab8-payments/payments/"
q() { python3 athena.py "$@"; }

case "${1:-}" in
  check)
    t() { if out="$("${@:2}" 2>&1)"; then echo "OK      $1"; else echo "DENIED  $1: $(echo "${out}" | tr '\n' ' ' | cut -c1-160)"; fi; }
    echo "region ${REGION}, account ${ACCOUNT}"
    t "s3: create bucket"      bash -c "aws s3api head-bucket --bucket ${BUCKET} 2>/dev/null || aws s3 mb s3://${BUCKET} --region ${REGION}"
    t "athena: start query"    aws athena start-query-execution --query-string "SELECT 1" --result-configuration "OutputLocation=s3://${BUCKET}/athena-results/"
    t "glue: list databases"   aws glue get-databases --max-results 1
    t "iam: get role"          aws iam list-roles --max-items 1
    t "kinesis: list streams"  aws kinesis list-streams --limit 1
    t "firehose: list streams" aws firehose list-delivery-streams --limit 1
    t "sns: list topics"       aws sns list-topics
    ;;
  setup)
    aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null || aws s3 mb "s3://${BUCKET}" --region "${REGION}"
    echo "==> copying ${SOURCE} to s3://${BUCKET}/payments/ (cross-region, about 1.2 GB)"
    if ! aws s3 sync "${SOURCE}" "s3://${BUCKET}/payments/" --source-region us-east-1 --only-show-errors; then
      # Reading a us-east-1 bucket may be refused for your account, but the bucket is public:
      # download it without signing, then upload from your own disk.
      echo "==> direct copy refused; downloading without credentials, then uploading"
      mkdir -p lab8-data
      AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= aws s3 sync "${SOURCE}" lab8-data/payments/ --no-sign-request --region us-east-1 --only-show-errors
      aws s3 sync lab8-data/payments/ "s3://${BUCKET}/payments/" --only-show-errors
    fi
    aws s3 ls "s3://${BUCKET}/payments/" --recursive --summarize | tail -2
    echo "Expect 31 days (dt=2026-10-01 .. dt=2026-10-31) and about 1.2 GB."
    ;;
  tables)
    q sql/q0_database.sql --database default
    q sql/q1_table.sql
    q sql/q1b_repair.sql
    q sql/q1c_count.sql
    ;;
  queries)
    q sql/q_scale.sql
    q sql/q2_view.sql
    q sql/q2b_check.sql
    for f in q3_turnover q4_failure_rate q5_peak_hours; do q "sql/${f}.sql" -D TABLE=payments --label json; done
    q sql/q6_late_events.sql
    ;;
  parquet)
    q sql/q7_parquet.sql
    for f in q3_turnover q4_failure_rate q5_peak_hours; do q "sql/${f}.sql" -D TABLE=payments_parquet --label parquet; done
    python3 compare.py
    ;;
  crawler)
    ROLE=lab8-glue-crawler
    if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
      aws iam create-role --role-name "${ROLE}" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
      aws iam attach-role-policy --role-name "${ROLE}" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
      aws iam put-role-policy --role-name "${ROLE}" --policy-name read-payments --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::${BUCKET}\",\"arn:aws:s3:::${BUCKET}/payments/*\"]}]}"
      echo "==> role created; waiting for IAM to settle"; sleep 15
    fi
    aws glue create-database --database-input Name=lab8_crawled 2>/dev/null || true
    aws glue create-crawler --name lab8-payments --role "${ROLE}" --database-name lab8_crawled \
      --targets "{\"S3Targets\":[{\"Path\":\"s3://${BUCKET}/payments/\"}]}" 2>/dev/null || true
    aws glue start-crawler --name lab8-payments
    echo "==> crawling (about 1-2 minutes)"
    while [[ "$(aws glue get-crawler --name lab8-payments --query Crawler.State --output text)" != "READY" ]]; do sleep 10; done
    aws glue get-crawler --name lab8-payments --query 'Crawler.LastCrawl.[Status,ErrorMessage]' --output text
    echo "--- columns the crawler chose ---"
    aws glue get-table --database-name lab8_crawled --name payments --query 'Table.StorageDescriptor.Columns[].[Name,Type]' --output text
    echo "--- partition keys ---"
    aws glue get-table --database-name lab8_crawled --name payments --query 'Table.PartitionKeys[].[Name,Type]' --output text
    ;;
  *)
    sed -n '2,9p' "$0"; exit 2 ;;
esac
