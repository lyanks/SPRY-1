#!/usr/bin/env bash
# Tear the backend down: ECS service, load balancer, RDS database, secret and
# (unless KEEP_IMAGES=1) the ECR repository. The database goes with it.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

STACK_NAME="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"

need aws
need_credentials
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1 \
  || die "stack ${STACK_NAME} does not exist in ${AWS_REGION}"

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "This deletes stack ${STACK_NAME} in ${AWS_REGION}, including the"
  echo "PostgreSQL database and everything in it."
  read -r -p "Type the stack name to confirm: " reply
  [[ "${reply}" == "${STACK_NAME}" ]] || die "aborted"
fi

log "deleting ${STACK_NAME} (ten minutes or so)"
aws cloudformation delete-stack --stack-name "${STACK_NAME}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"

# Secrets Manager schedules deletions, and the name stays taken for the whole
# recovery window - which would block the next deploy.
SECRET_NAME="${PROJECT_NAME}/backend/db"
if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
  log "force-deleting the ${SECRET_NAME} secret so the name is free again"
  aws secretsmanager delete-secret --secret-id "${SECRET_NAME}" \
    --force-delete-without-recovery >/dev/null
fi

if [[ "${KEEP_IMAGES:-0}" != "1" ]]; then
  if aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" >/dev/null 2>&1; then
    log "deleting the ${ECR_REPOSITORY} ECR repository"
    aws ecr delete-repository --repository-name "${ECR_REPOSITORY}" --force >/dev/null
  fi
fi

env_set BACKEND_URL ""
log "backend removed"
