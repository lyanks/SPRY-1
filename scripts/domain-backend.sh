#!/usr/bin/env bash
# Request + DNS-validate the ACM certificate for the API's domain, in the
# backend's own region (an ALB cannot use a us-east-1 certificate from
# elsewhere). Run before `make deploy-backend`; the deploy then turns HTTPS on,
# redirects port 80 to 443 and, if the zone is in Route 53, creates the record.
#
#   make cert-backend API_DOMAIN=api.example.com
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

DOMAIN="${API_DOMAIN:-}"
DOMAIN="${DOMAIN%.}"
[[ -n "${DOMAIN}" ]] || die "no domain - run: make cert-backend API_DOMAIN=api.example.com"

need aws python3
need_credentials

ZONE_ID=""
read -r ZONE_ID _ <<<"$(find_hosted_zone "${DOMAIN}")" || true
if [[ -n "${ZONE_ID}" ]]; then
  log "${DOMAIN} sits in Route 53 zone ${ZONE_ID}"
else
  warn "no Route 53 zone covers ${DOMAIN} - you will add DNS records by hand"
fi

CERT_ARN="$(aws acm list-certificates --certificate-statuses PENDING_VALIDATION ISSUED \
  --query "CertificateSummaryList[?DomainName=='${DOMAIN}']|[0].CertificateArn" \
  --output text 2>/dev/null || true)"

if [[ -z "${CERT_ARN}" || "${CERT_ARN}" == "None" ]]; then
  log "requesting an ACM certificate for ${DOMAIN} in ${AWS_REGION}"
  CERT_ARN="$(aws acm request-certificate --domain-name "${DOMAIN}" \
    --validation-method DNS --key-algorithm RSA_2048 \
    --tags "Key=PROJECT_NAME,Value=${PROJECT_NAME}" \
    --query CertificateArn --output text)"
else
  log "reusing the existing certificate for ${DOMAIN}"
fi

status() {
  aws acm describe-certificate --certificate-arn "${CERT_ARN}" \
    --query Certificate.Status --output text
}

if [[ "$(status)" != "ISSUED" ]]; then
  RECORD=""
  for _ in $(seq 1 12); do
    RECORD="$(aws acm describe-certificate --certificate-arn "${CERT_ARN}" \
      --query "Certificate.DomainValidationOptions[0].ResourceRecord.[Name,Type,Value]" \
      --output text 2>/dev/null || true)"
    [[ -n "${RECORD}" && "${RECORD}" != *"None"* ]] && break
    sleep 5
  done
  [[ -n "${RECORD}" && "${RECORD}" != *"None"* ]] || die "ACM published no validation record"
  read -r NAME TYPE VALUE <<<"${RECORD}"

  if [[ -n "${ZONE_ID}" ]]; then
    log "adding the validation record to Route 53"
    CHANGE_FILE="$(mktemp)"
    trap 'rm -f "${CHANGE_FILE}"' EXIT
    cat >"${CHANGE_FILE}" <<JSON
{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
  "Name":"${NAME}","Type":"${TYPE}","TTL":300,
  "ResourceRecords":[{"Value":"${VALUE}"}]}}]}
JSON
    aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" \
      --change-batch "file://${CHANGE_FILE}" >/dev/null
  else
    echo
    echo "  Add this record wherever ${DOMAIN} is hosted, then leave this running:"
    echo "    name   ${NAME}"
    echo "    type   ${TYPE}"
    echo "    value  ${VALUE}"
    echo
  fi

  log "waiting for validation (minutes, once DNS propagates)"
  for _ in $(seq 1 120); do
    case "$(status)" in
      ISSUED) break ;;
      PENDING_VALIDATION) printf '.'; sleep 15 ;;
      *) echo; die "certificate failed validation - see ACM in the console" ;;
    esac
  done
  echo
fi

[[ "$(status)" == "ISSUED" ]] || die "gave up waiting - re-run once DNS is published"
env_set API_DOMAIN "${DOMAIN}"
echo
echo "Certificate ready. Now: make deploy-backend"
