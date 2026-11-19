#!/usr/bin/env bash
# Lab 8, Part 4: Kinesis -> Firehose -> S3 -> Athena, with an SNS alert. From the project root:
#   bash lab8/part4/part4.sh up       create the role, Kinesis stream, Firehose stream, SNS topic, Athena table
#   bash lab8/part4/part4.sh run      replay 30 minutes of payments into Kinesis, alert from the stream, wait for S3
#   bash lab8/part4/part4.sh query    Athena queries over the streamed data (also run them in the console for the screenshot)
#   bash lab8/part4/part4.sh down     DELETE the Firehose and Kinesis streams, the topic and the role, and print the cost
# Optional: ALERT_EMAIL=you@example.com bash lab8/part4/part4.sh up   (SNS sends you a confirmation e-mail)
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "${SELF}")"

[ -n "${AWS_PROFILE-x}" ] || unset AWS_PROFILE
REGION="${LAB8_REGION:-eu-north-1}"
export AWS_REGION="${REGION}" AWS_DEFAULT_REGION="${REGION}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
export BUCKET="${BUCKET:-spry-lab8-${ACCOUNT}}"

STREAM=lab8-payments
FIREHOSE=lab8-payments-to-s3
ROLE=lab8-firehose
TOPIC=lab8-payment-alerts
PY="../part3/.venv/bin/python"
RATE="${RATE:-20}"
FROM="${SLICE_FROM:-17:00}"
TO="${SLICE_TO:-17:30}"
mkdir -p logs

case "${1:-}" in
  up)
    date +%s > logs/up.timestamp
    "${PY}" -m pip install -q boto3
    STREAM_ARN="arn:aws:kinesis:${REGION}:${ACCOUNT}:stream/${STREAM}"

    echo "==> IAM role ${ROLE} (Firehose reads Kinesis, writes S3)"
    aws iam create-role --role-name "${ROLE}" --assume-role-policy-document '{
      "Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
      --query Role.Arn --output text >/dev/null || true
    aws iam put-role-policy --role-name "${ROLE}" --policy-name lab8-firehose --policy-document "{
      \"Version\":\"2012-10-17\",\"Statement\":[
        {\"Effect\":\"Allow\",\"Action\":[\"kinesis:DescribeStream\",\"kinesis:GetShardIterator\",\"kinesis:GetRecords\",\"kinesis:ListShards\"],\"Resource\":\"${STREAM_ARN}\"},
        {\"Effect\":\"Allow\",\"Action\":[\"s3:AbortMultipartUpload\",\"s3:GetBucketLocation\",\"s3:GetObject\",\"s3:ListBucket\",\"s3:ListBucketMultipartUploads\",\"s3:PutObject\"],
         \"Resource\":[\"arn:aws:s3:::${BUCKET}\",\"arn:aws:s3:::${BUCKET}/*\"]}]}"
    ROLE_ARN="$(aws iam get-role --role-name "${ROLE}" --query Role.Arn --output text)"

    echo "==> Kinesis stream ${STREAM} (1 shard, provisioned)"
    aws kinesis create-stream --stream-name "${STREAM}" --shard-count 1 2>/dev/null || echo "(stream already exists)"
    aws kinesis wait stream-exists --stream-name "${STREAM}"

    echo "==> Firehose ${FIREHOSE}: Kinesis -> s3://${BUCKET}/stream/ (a file every 60 s)"
    sleep 10   # a new IAM role needs a few seconds before Firehose can use it
    for attempt in 1 2 3 4 5 6; do
      if aws firehose create-delivery-stream --delivery-stream-name "${FIREHOSE}" \
           --delivery-stream-type KinesisStreamAsSource \
           --kinesis-stream-source-configuration "KinesisStreamARN=${STREAM_ARN},RoleARN=${ROLE_ARN}" \
           --extended-s3-destination-configuration "{
             \"RoleARN\":\"${ROLE_ARN}\",\"BucketARN\":\"arn:aws:s3:::${BUCKET}\",
             \"Prefix\":\"stream/dt=!{timestamp:yyyy-MM-dd}/\",
             \"ErrorOutputPrefix\":\"stream-errors/!{firehose:error-output-type}/\",
             \"BufferingHints\":{\"SizeInMBs\":1,\"IntervalInSeconds\":60},
             \"CompressionFormat\":\"UNCOMPRESSED\"}" >/dev/null 2>logs/firehose-create.err; then
        break
      fi
      if grep -q "ResourceInUse" logs/firehose-create.err; then echo "(delivery stream already exists)"; break; fi
      echo "  role not ready, retrying ($attempt/6): $(head -c 160 logs/firehose-create.err)"; sleep 10
    done

    echo "==> SNS topic ${TOPIC}"
    TOPIC_ARN="$(aws sns create-topic --name "${TOPIC}" --query TopicArn --output text)"
    echo "${TOPIC_ARN}" > logs/topic.arn
    if [ -n "${ALERT_EMAIL:-}" ]; then
      aws sns subscribe --topic-arn "${TOPIC_ARN}" --protocol email --notification-endpoint "${ALERT_EMAIL}" >/dev/null
      echo "    confirmation e-mail sent to ${ALERT_EMAIL}: click the link in it"
    fi

    echo "==> Athena table lab8.stream_events"
    python3 ../athena.py sql/s0_table.sql
    echo; echo "streams:"
    aws kinesis list-streams --output text --query 'StreamNames'
    aws firehose list-delivery-streams --output text --query 'DeliveryStreamNames'
    ;;
  run)
    TOPIC_ARN="$(cat logs/topic.arn)"
    "${PY}" producer_kinesis.py --stream "${STREAM}" --from "${FROM}" --to "${TO}" --rate "${RATE}" \
        ${FAIL_PCT:+--fail-pct "${FAIL_PCT}"} > logs/producer.log 2>&1 &
    PROD=$!
    sleep 5
    "${PY}" alerter.py --stream "${STREAM}" --topic-arn "${TOPIC_ARN}" 2>&1 | tee logs/alerter.log
    wait "${PROD}" || true
    tail -2 logs/producer.log
    echo "==> waiting for Firehose to write the files to S3 (it flushes every 60 s)"
    for _ in $(seq 20); do
      n="$(aws s3 ls "s3://${BUCKET}/stream/" --recursive | wc -l)"
      [ "${n}" -gt 0 ] && break
      sleep 10
    done
    sleep 70   # the last buffer
    aws s3 ls "s3://${BUCKET}/stream/" --recursive --human-readable --summarize | tail -8
    ;;
  query)
    python3 ../athena.py sql/s2_count.sql
    python3 ../athena.py sql/s1_failure_rate.sql
    ;;
  down)
    echo "==> deleting the Firehose and Kinesis streams (they bill per hour while they exist)"
    aws firehose delete-delivery-stream --delivery-stream-name "${FIREHOSE}" 2>&1 | head -2 || true
    aws kinesis delete-stream --stream-name "${STREAM}" --enforce-consumer-deletion 2>&1 | head -2 || true
    [ -s logs/topic.arn ] && aws sns delete-topic --topic-arn "$(cat logs/topic.arn)" || true
    aws iam delete-role-policy --role-name "${ROLE}" --policy-name lab8-firehose 2>/dev/null || true
    aws iam delete-role --role-name "${ROLE}" 2>/dev/null || true
    sleep 15
    echo; echo "--- what is left (all three lists must be empty) ---"
    echo "kinesis:  $(aws kinesis list-streams --query 'StreamNames' --output text)"
    echo "firehose: $(aws firehose list-delivery-streams --query 'DeliveryStreamNames' --output text)"
    echo "role:     $(aws iam list-roles --query "Roles[?RoleName=='${ROLE}'].RoleName" --output text)"
    if [ -s logs/up.timestamp ]; then
      python3 - <<'EOF'
import time
hours = (time.time() - int(open("logs/up.timestamp").read())) / 3600
print(f"\nthe streams existed about {hours * 60:.0f} minutes")
print(f"shard hours: {hours:.2f} x $0.015 = about ${hours * 0.015:.3f} (eu-north-1 price, check the pricing page)")
print("Firehose, PutRecords, S3 and Athena for ~3,600 events: well under one cent")
EOF
    fi
    ;;
  *)
    sed -n '2,7p' "${SELF}"; exit 2 ;;
esac
