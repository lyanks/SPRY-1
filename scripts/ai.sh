#!/usr/bin/env bash
# Paste an agenda (Lab 6).
#
#   scripts/ai.sh deploy     build the Lambda image, push it, deploy infra/ai.yml
#   scripts/ai.sh budget     create the $5 monthly AWS Budgets alarm (make deploy-ai does it too)
#   scripts/ai.sh logs       the last hour of the parser's log lines (one JSON line per parse)
#   scripts/ai.sh destroy    delete the stack
#
# Needs the auth stack first (make deploy-auth): the function checks its tokens.
# Then run make deploy-frontend again, so the site is built with the function's URL.
#
# Optional in .env: PARSER_MODEL (default global.anthropic.claude-haiku-4-5-20251001-v1:0),
# PARSER_API (runtime | mantle), PARSER_EFFORT (Claude 5.x only), BEDROCK_REGION
# (default us-east-1), BUDGET_EMAIL (default REPORT_EMAIL).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

MODE="${1:-}"
STACK="${AI_STACK_NAME:-${PROJECT_NAME}-ai}"
AUTH_STACK="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
FRONTEND_STACK="${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}"
ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"

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
  deploy)
    need git docker

    POOL_ID="$(stack_output "${AUTH_STACK}" UserPoolId)"
    CLIENT_ID="$(stack_output "${AUTH_STACK}" ClientId)"
    [[ -n "${POOL_ID}" && "${POOL_ID}" != "None" ]] || die "deploy sign-in first: make deploy-auth"

    # Browsers allowed to call the function URL: the site, a custom domain, local dev.
    origins=("http://localhost:3000")
    [[ -n "${APP_DOMAIN:-}" ]] && origins+=("https://${APP_DOMAIN%.}")
    site="$(stack_output "${FRONTEND_STACK}" SiteUrl)"
    [[ -n "${site}" && "${site}" != "None" ]] && origins+=("${site%/}")
    ORIGINS="$(IFS=,; echo "${origins[*]}")"

    TAG="ai-$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
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

    log "deploying ${STACK}"
    aws cloudformation deploy \
      --stack-name "${STACK}" \
      --template-file "${ROOT}/infra/ai.yml" \
      --capabilities CAPABILITY_NAMED_IAM \
      --no-fail-on-empty-changeset \
      --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" "ImageUri=${IMAGE_URI}" \
        "CognitoRegion=${AWS_REGION}" "CognitoUserPoolId=${POOL_ID}" "CognitoClientId=${CLIENT_ID}" \
        "AllowedOrigins=${ORIGINS}" \
        "ParserModel=${PARSER_MODEL:-global.anthropic.claude-haiku-4-5-20251001-v1:0}" \
        "ParserApi=${PARSER_API:-runtime}" \
        "ParserEffort=${PARSER_EFFORT:-}" \
        "BedrockRegion=${BEDROCK_REGION:-us-east-1}" \
      --tags "PROJECT_NAME=${PROJECT_NAME}" || { print_failed_events "${STACK}"; exit 1; }

    create_budget

    echo
    echo "  parser  $(stack_output "${STACK}" ParserUrl)"
    echo "  next    make deploy-frontend   (the site must be rebuilt to know this URL)"
    ;;

  budget)
    create_budget
    ;;

  logs)
    aws logs tail "/aws/lambda/${PROJECT_NAME}-agenda-parser" --since 1h --format short \
      | grep agenda_parsed || echo "no parses in the last hour"
    ;;

  destroy)
    aws cloudformation delete-stack --stack-name "${STACK}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
    log "ai stack removed"
    ;;

  *) echo "usage: $0 deploy | budget | logs | destroy" >&2; exit 2 ;;
esac
