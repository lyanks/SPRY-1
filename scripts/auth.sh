#!/usr/bin/env bash
# Sign-in with Amazon Cognito (Lab 4).
#
#   scripts/auth.sh uris      what to paste into Google's OAuth client (needs no stack)
#   scripts/auth.sh deploy    create/update the Cognito stack (infra/auth.yaml)
#   scripts/auth.sh destroy   delete it
#
# Order: make deploy-frontend (the stack needs the site's URL) -> make auth-uris
# (paste into Google) -> GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET in .env ->
# make deploy-auth -> make deploy-frontend again (it now builds with sign-in).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/auth.yaml"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  # Variables already exported win over .env.
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
  eval "${preset}"
fi

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
FRONTEND_STACK="${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

command -v aws >/dev/null 2>&1 || die "aws is required but not installed"
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no usable AWS credentials - set AWS_PROFILE or the AWS_* keys in .env"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
# The same prefix infra/auth.yaml builds for the Cognito domain.
COGNITO_DOMAIN="https://${PROJECT_NAME}-${ACCOUNT_ID}.auth.${AWS_REGION}.amazoncognito.com"

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text 2>/dev/null || true
}

case "${1:-}" in
  uris)
    echo
    echo "In the Google Cloud console -> Google Auth Platform -> Clients -> your Web application client:"
    echo
    echo "  Authorised JavaScript origin   ${COGNITO_DOMAIN}"
    echo "  Authorised redirect URI        ${COGNITO_DOMAIN}/oauth2/idpresponse"
    echo
    echo "Then put the client ID and secret in .env:"
    echo "  GOOGLE_CLIENT_ID=..."
    echo "  GOOGLE_CLIENT_SECRET=..."
    echo
    ;;

  deploy)
    [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]] \
      || die "set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env (make auth-uris says where to get them)"

    SITE_URL="$(stack_output "${FRONTEND_STACK}" SiteUrl)"
    [[ -n "${SITE_URL}" && "${SITE_URL}" != "None" ]] \
      || die "no ${FRONTEND_STACK} stack - run make deploy-frontend first (Cognito needs the site's URL)"

    log "deploying ${STACK_NAME} for ${SITE_URL}"
    if ! aws cloudformation deploy \
      --stack-name "${STACK_NAME}" \
      --template-file "${TEMPLATE}" \
      --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "SiteUrl=${SITE_URL}" \
        "GoogleClientId=${GOOGLE_CLIENT_ID}" \
        "GoogleClientSecret=${GOOGLE_CLIENT_SECRET}" \
      --no-fail-on-empty-changeset \
      --tags "PROJECT_NAME=${PROJECT_NAME}"; then
      warn "deploy failed - most recent failure reasons:"
      aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
        --max-items 40 \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
        --output table >&2 || true
      exit 1
    fi

    echo
    echo "  user pool   $(stack_output "${STACK_NAME}" UserPoolId)"
    echo "  client      $(stack_output "${STACK_NAME}" ClientId)"
    echo "  cognito     $(stack_output "${STACK_NAME}" CognitoDomain)"
    echo "  login page  $(stack_output "${STACK_NAME}" LoginUrl)"
    echo
    echo "Next: make deploy-frontend (rebuilds the site with sign-in), then open the login page."
    echo
    ;;

  destroy)
    log "deleting ${STACK_NAME}"
    aws cloudformation delete-stack --stack-name "${STACK_NAME}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
    log "${STACK_NAME} removed (users included)"
    echo "Run make deploy-frontend to rebuild the site without sign-in."
    ;;

  *)
    echo "usage: $0 uris | deploy | destroy" >&2
    exit 2
    ;;
esac
