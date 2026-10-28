#!/usr/bin/env bash
# Sign-in with Amazon Cognito (Lab 4). The user pool itself is Terraform since Lab 7
# (infra/auth.tf); this script only prints what Google's OAuth client must list.
#
#   scripts/auth.sh uris      (needs no Terraform run: the domain is built from the account id)
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
need aws
need_credentials

case "${1:-}" in
  uris)
    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    COGNITO_DOMAIN="https://${PROJECT_NAME}-${ACCOUNT_ID}.auth.${AWS_REGION}.amazoncognito.com"
    echo
    echo "In the Google Cloud console -> Google Auth Platform -> Clients -> your Web application client:"
    echo
    echo "  Authorised JavaScript origin   ${COGNITO_DOMAIN}"
    echo "  Authorised redirect URI        ${COGNITO_DOMAIN}/oauth2/idpresponse"
    echo
    echo "Then set google_client_id and (sensitive) google_client_secret in the HCP Terraform workspace."
    echo
    ;;
  *)
    echo "usage: $0 uris" >&2
    exit 2
    ;;
esac
