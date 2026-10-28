#!/usr/bin/env bash
# Paste an agenda (Lab 6). The function is Terraform since Lab 7 (infra/ai.tf).
#
#   scripts/ai.sh budget     create the $5 monthly AWS Budgets alarm
#   scripts/ai.sh logs       the last hour of the parser's log lines (one JSON line per parse)
#
# Optional in .env: BUDGET_EMAIL (default REPORT_EMAIL), BUDGET_LIMIT_USD (default 5).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

MODE="${1:-}"
need aws python3
need_credentials

# The cheapest insurance in the course (Lab 6, Step 6): an email when the account's
# month-to-date cost passes 80% and 100% of $5. Budgets is a global service whose API
# lives in us-east-1, and its CloudFormation resource is not available in every region,
# so it is created here. Safe to repeat; a failure only warns.
create_budget() {
  local email="${BUDGET_EMAIL:-${REPORT_EMAIL:-}}" limit="${BUDGET_LIMIT_USD:-5}" account name
  [[ -n "${email}" ]] || { warn "no BUDGET_EMAIL or REPORT_EMAIL in .env - skipping the budget alarm"; return 0; }
  account="$(aws sts get-caller-identity --query Account --output text)"
  name="${PROJECT_NAME}-monthly"
  if aws budgets describe-budget --region us-east-1 --account-id "${account}" \
    --budget-name "${name}" >/dev/null 2>&1; then
    log "budget ${name} already exists"
    return 0
  fi
  local budget notifications
  budget="$(LIMIT="${limit}" NAME="${name}" python3 -c 'import json,os; print(json.dumps({"BudgetName":os.environ["NAME"],"BudgetType":"COST","TimeUnit":"MONTHLY","BudgetLimit":{"Amount":os.environ["LIMIT"],"Unit":"USD"}}))')"
  notifications="$(EMAIL="${email}" python3 -c 'import json,os; print(json.dumps([{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":t,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":os.environ["EMAIL"]}]} for t in (80,100)]))')"
  if aws budgets create-budget --region us-east-1 --account-id "${account}" \
    --budget "${budget}" --notifications-with-subscribers "${notifications}"; then
    log "budget ${name}: \$${limit} a month, email to ${email} at 80% and 100%"
  else
    warn "could not create the budget (permissions?). Create it by hand: Billing -> Budgets -> a \$${limit} monthly cost budget with an email alert."
  fi
}

case "${MODE}" in
  budget)
    create_budget
    ;;

  logs)
    aws logs tail "/aws/lambda/${PROJECT_NAME}-agenda-parser" --since 1h --format short \
      | grep agenda_parsed || echo "no parses in the last hour"
    ;;

  *) echo "usage: $0 budget | logs" >&2; exit 2 ;;
esac
