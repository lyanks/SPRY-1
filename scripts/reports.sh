#!/usr/bin/env bash
# The weekly report (Lab 5). The infrastructure is Terraform since Lab 7 (infra/reports.tf).
#
#   scripts/reports.sh now [WEEK]     put a "build this week" message on the queue (default: last week)
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

MODE="${1:-}"
need aws python3
need_credentials

case "${MODE}" in
  now)
    WEEK="${2:-${WEEK:-}}"
    if [[ -z "${WEEK}" ]]; then
      WEEK="$(python3 -c "import datetime as d; y,w,_=(d.date.today()-d.timedelta(days=7)).isocalendar(); print(f'{y}-W{w:02d}')")"
    fi
    [[ "${WEEK}" =~ ^[0-9]{4}-W[0-9]{2}$ ]] || die "WEEK must look like 2026-W40"
    QUEUE_URL="$(tf_output report_queue_url REPORT_QUEUE_URL)"
    [[ -n "${QUEUE_URL}" ]] || die "no queue URL: is the infrastructure applied? (make infra-output)"
    log "asking for the report of ${WEEK}"
    aws sqs send-message --queue-url "${QUEUE_URL}" \
      --message-body "{\"week\": \"${WEEK}\", \"source\": \"make\"}"
    echo "  watch   aws logs tail /aws/lambda/${PROJECT_NAME}-report-builder --since 5m"
    echo "  files   aws s3 ls s3://${PROJECT_NAME}-reports-$(aws sts get-caller-identity --query Account --output text)/reports/ --recursive"
    ;;

  *) echo "usage: $0 now [WEEK]" >&2; exit 2 ;;
esac
