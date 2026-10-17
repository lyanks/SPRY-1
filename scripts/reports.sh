#!/usr/bin/env bash
# The weekly report (Lab 3).
#
#   scripts/reports.sh deploy         (SCHEDULE='rate(5 minutes)' FAIL_WEEK=2026-W39 for the Step 7 tests)
#                                     build the Lambda image, push it, deploy infra/reports.yaml
#   scripts/reports.sh now [WEEK]     put a "build this week" message on the queue (default: last week)
#   scripts/reports.sh destroy        empty the bucket and delete the stack
#
# Needs the backend stack first (the builder reads its database), and REPORT_EMAIL
# in .env: an SES identity you have verified (a new account is in the SES sandbox).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

MODE="${1:-}"
STACK="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
BACKEND_STACK="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"

need aws python3
need_credentials

case "${MODE}" in
  deploy)
    [[ -n "${REPORT_EMAIL:-}" ]] || die "set REPORT_EMAIL in .env to an SES-verified address"
    need git docker

    DB_HOST="$(stack_output "${BACKEND_STACK}" DatabaseEndpoint)"
    DB_SG="$(stack_output "${BACKEND_STACK}" DatabaseSecurityGroupId)"
    [[ -n "${DB_HOST}" && "${DB_HOST}" != "None" ]] || die "deploy the backend first: make deploy-backend"
    [[ -n "${DB_SG}" && "${DB_SG}" != "None" ]] || die "redeploy the backend once (make deploy-backend) so it exports its database security group"

    TAG="reports-$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
    [[ -z "$(git -C "${ROOT}" status --porcelain)" ]] || TAG="${TAG}-dirty-$(date +%s)"
    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${TAG}"

    if ! aws ecr describe-images --repository-name "${ECR_REPOSITORY}" \
      --image-ids "imageTag=${TAG}" >/dev/null 2>&1; then
      log "building the Lambda image ${TAG}"
      aws ecr get-login-password | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
      # Lambda wants a single-platform image manifest, not a build with attestations.
      docker build --platform linux/amd64 --provenance=false --target lambda \
        -t "${IMAGE_URI}" "${ROOT}/backend"
      docker push "${IMAGE_URI}"
    fi

    VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
      --query 'Vpcs[0].VpcId' --output text)}"
    SUBNET_IDS="${SUBNET_IDS:-$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${VPC_ID}" Name=default-for-az,Values=true \
      --query 'Subnets[].SubnetId' --output text | tr '\t' ',')}"
    ROUTE_TABLES="$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'RouteTables[?Associations[?Main==`true`]].RouteTableId' --output text | tr '\t' ',')"
    [[ -n "${ROUTE_TABLES}" ]] || die "could not find the VPC's main route table"

    log "deploying ${STACK}"
    aws cloudformation deploy \
      --stack-name "${STACK}" \
      --template-file "${ROOT}/infra/reports.yaml" \
      --capabilities CAPABILITY_NAMED_IAM \
      --no-fail-on-empty-changeset \
      --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" "ImageUri=${IMAGE_URI}" "VpcId=${VPC_ID}" \
        "SubnetIds=${SUBNET_IDS}" "RouteTableIds=${ROUTE_TABLES}" \
        "DatabaseSecurityGroupId=${DB_SG}" "DatabaseHost=${DB_HOST}" \
        "ReportEmail=${REPORT_EMAIL}" \
        "ScheduleExpression=${SCHEDULE:-cron(0 7 ? * MON *)}" "FailWeek=${FAIL_WEEK:-}" \
      --tags "PROJECT_NAME=${PROJECT_NAME}" || { print_failed_events "${STACK}"; exit 1; }

    echo
    echo "  bucket  $(stack_output "${STACK}" BucketName)"
    echo "  next    make report-now WEEK=<an ISO week, e.g. 2026-W41>"
    ;;

  now)
    WEEK="${2:-${WEEK:-}}"
    if [[ -z "${WEEK}" ]]; then
      WEEK="$(python3 -c "import datetime as d; y,w,_=(d.date.today()-d.timedelta(days=7)).isocalendar(); print(f'{y}-W{w:02d}')")"
    fi
    [[ "${WEEK}" =~ ^[0-9]{4}-W[0-9]{2}$ ]] || die "WEEK must look like 2026-W40"
    QUEUE_URL="$(stack_output "${STACK}" QueueUrl)"
    [[ -n "${QUEUE_URL}" && "${QUEUE_URL}" != "None" ]] || die "deploy first: make deploy-reports"
    log "asking for the report of ${WEEK}"
    aws sqs send-message --queue-url "${QUEUE_URL}" \
      --message-body "{\"week\": \"${WEEK}\", \"source\": \"make\"}"
    echo "  watch   aws logs tail /aws/lambda/${PROJECT_NAME}-report-builder --since 5m"
    echo "  files   aws s3 ls s3://${PROJECT_NAME}-reports-$(aws sts get-caller-identity --query Account --output text)/reports/ --recursive"
    ;;

  destroy)
    BUCKET="$(stack_output "${STACK}" BucketName)"
    [[ -z "${BUCKET}" || "${BUCKET}" == "None" ]] || aws s3 rm "s3://${BUCKET}" --recursive >/dev/null
    aws cloudformation delete-stack --stack-name "${STACK}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
    log "reports stack removed"
    ;;

  *) echo "usage: $0 deploy | now [WEEK] | destroy" >&2; exit 2 ;;
esac
