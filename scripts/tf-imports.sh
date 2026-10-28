#!/usr/bin/env bash
# Lab 7, Part 2 Step 3b: write infra/imports.tf from what really exists in AWS.
#
#   scripts/tf-imports.sh            writes infra/imports.tf
#
# Run it BEFORE you delete the CloudFormation stacks (3a), or after: it looks
# resources up by name and by filter, not through the stacks. A resource it cannot
# find is written as a comment, so the plan then shows "1 to add" for it.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
need aws python3
need_credentials

P="${PROJECT_NAME}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
OUT="${ROOT}/infra/imports.tf"

none() { [[ -z "${1:-}" || "${1}" == "None" || "${1}" == "null" ]]; }

: >"${OUT}"
{
  echo "# Written by scripts/tf-imports.sh. Delete this file after the migration (Lab 7, Step 3c)."
  echo
} >>"${OUT}"

imp() { # imp <address> <id> [note]
  if none "$2"; then
    printf '# not found in AWS, Terraform will create it: %s\n\n' "$1" >>"${OUT}"
    warn "not found: $1"
  else
    printf 'import {\n  to = %s\n  id = "%s"\n}\n\n' "$1" "$2" >>"${OUT}"
  fi
}

q() { "$@" --output text 2>/dev/null || true; }

# ---- auth (Lab 4) --------------------------------------------------------
POOL="$(q aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='${P}-users'].Id | [0]")"
CLIENT=""
BRANDING=""
if ! none "${POOL}"; then
  CLIENT="$(q aws cognito-idp list-user-pool-clients --user-pool-id "${POOL}" --max-results 60 \
    --query "UserPoolClients[?ClientName=='${P}-web'].ClientId | [0]")"
  if ! none "${CLIENT}"; then
    BRANDING="$(q aws cognito-idp describe-managed-login-branding-by-client --user-pool-id "${POOL}" \
      --client-id "${CLIENT}" --query 'ManagedLoginBranding.ManagedLoginBrandingId')"
  fi
fi
imp aws_cognito_user_pool.main "${POOL}"
if ! none "${POOL}"; then imp aws_cognito_identity_provider.google "${POOL}:Google"; fi
if ! none "${CLIENT}"; then imp aws_cognito_user_pool_client.web "${POOL}/${CLIENT}"; fi
imp aws_cognito_user_pool_domain.main "${P}-${ACCOUNT}"
if none "${BRANDING}"; then BRANDING=""; else BRANDING="${POOL},${BRANDING}"; fi
imp aws_cognito_managed_login_branding.main "${BRANDING}"

# ---- reports (Lab 5) -----------------------------------------------------
BUCKET="${P}-reports-${ACCOUNT}"
imp aws_s3_bucket.reports "${BUCKET}"
imp aws_s3_bucket_public_access_block.reports "${BUCKET}"
imp aws_s3_bucket_lifecycle_configuration.reports "${BUCKET}"
imp aws_s3_bucket_notification.reports "${BUCKET}"

BUILDER="${P}-report-builder"
MAILER="${P}-report-mailer"
VPC="$(q aws lambda get-function-configuration --function-name "${BUILDER}" --query 'VpcConfig.VpcId')"
BSG="$(q aws lambda get-function-configuration --function-name "${BUILDER}" --query 'VpcConfig.SecurityGroupIds[0]')"
if ! none "${VPC}"; then
  VPCE="$(q aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${VPC}" "Name=service-name,Values=com.amazonaws.${AWS_REGION}.s3" \
    --query 'VpcEndpoints[0].VpcEndpointId')"
  imp aws_vpc_endpoint.s3 "${VPCE}"
fi
imp aws_security_group.builder "${BSG}"
if [[ -f "${ROOT}/infra/terraform.tfvars" ]]; then
  DBSG="$(sed -n 's/^database_security_group_id *= *"\(.*\)"/\1/p' "${ROOT}/infra/terraform.tfvars")"
  if ! none "${DBSG}" && ! none "${BSG}"; then
    RULE="$(q aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${DBSG}" \
      --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='${BSG}'] | [0].SecurityGroupRuleId")"
    imp aws_vpc_security_group_ingress_rule.database_from_builder "${RULE}"
  fi
fi

DLQ="$(q aws sqs get-queue-url --queue-name "${P}-report-requests-dlq" --query QueueUrl)"
REQ="$(q aws sqs get-queue-url --queue-name "${P}-report-requests" --query QueueUrl)"
imp aws_sqs_queue.dead_letter "${DLQ}"
imp aws_sqs_queue.requests "${REQ}"

imp aws_iam_role.scheduler "${P}-report-scheduler"
imp aws_iam_role_policy.scheduler_send_to_queue "${P}-report-scheduler:send-to-queue"
imp aws_scheduler_schedule.weekly "default/${P}-weekly-report"
imp aws_iam_role.builder "${BUILDER}"
imp aws_iam_role_policy_attachment.builder_vpc "${BUILDER}/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
imp aws_iam_role_policy.builder_reports "${BUILDER}:reports"
imp aws_lambda_function.builder "$(q aws lambda get-function --function-name "${BUILDER}" --query 'Configuration.FunctionName')"
MAPPING="$(q aws lambda list-event-source-mappings --function-name "${BUILDER}" --query 'EventSourceMappings[0].UUID')"
imp aws_lambda_event_source_mapping.requests "${MAPPING}"
imp aws_iam_role.mailer "${MAILER}"
imp aws_iam_role_policy_attachment.mailer_logs "${MAILER}/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
imp aws_iam_role_policy.mailer_read_and_send "${MAILER}:read-and-send"
imp aws_lambda_function.mailer "$(q aws lambda get-function --function-name "${MAILER}" --query 'Configuration.FunctionName')"

# ---- ai (Lab 6) ----------------------------------------------------------
PARSER="${P}-agenda-parser"
imp aws_iam_role.parser "${PARSER}"
imp aws_iam_role_policy_attachment.parser_logs "${PARSER}/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
imp aws_iam_role_policy.parser_call_claude "${PARSER}:call-claude"
imp aws_cloudwatch_log_group.parser "/aws/lambda/${PARSER}"
imp aws_lambda_function.parser "$(q aws lambda get-function --function-name "${PARSER}" --query 'Configuration.FunctionName')"
# The import id of a function URL is the function's name.
URL_OF_PARSER="$(q aws lambda get-function-url-config --function-name "${PARSER}" --query FunctionUrl)"
if none "${URL_OF_PARSER}"; then imp aws_lambda_function_url.parser ""; else imp aws_lambda_function_url.parser "${PARSER}"; fi

# Not imported on purpose (Terraform creates them fresh, which is safe):
#   aws_lambda_permission.*  the old statements have CloudFormation-made ids and stay harmlessly
#   data sources, archive_file
cat <<MSG

Wrote ${OUT}
Imports: $(grep -c '^import' "${OUT}"). Not found (will be created): $(grep -c '^# not found' "${OUT}").
Next: terraform -chdir=infra plan
MSG
