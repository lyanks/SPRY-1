#!/usr/bin/env bash
# Ship the backend: build the image, push it to ECR tagged with the commit SHA,
# and roll the ECS service to it. This is `make deploy-backend`, and the very
# same script CI runs, so a failed deploy can be reproduced on a laptop.
#
#   make deploy-backend                       build + push + roll out HEAD
#   IMAGE_TAG=3f2a9c1d4e5b make deploy-backend   roll back: redeploy an older tag
#                                              (the image is already in ECR, so
#                                              nothing is rebuilt)
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env

STACK_NAME="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
TEMPLATE="${ROOT}/infra/backend.yaml"
ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"

need aws git python3
need_credentials

# --- which image ------------------------------------------------------------

if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
  # An image tagged with a commit that does not contain what was built is worse
  # than no tag at all.
  if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
    warn "the working tree has uncommitted changes - tagging the image ${IMAGE_TAG}-dirty"
    IMAGE_TAG="${IMAGE_TAG}-dirty-$(date +%s)"
  fi
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# --- registry ---------------------------------------------------------------

# Created here rather than by the stack: the image has to exist before the
# service can start, and the service is part of the stack.
if ! aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" >/dev/null 2>&1; then
  log "creating the ${ECR_REPOSITORY} ECR repository"
  # IMMUTABLE: a tag, once pushed, can never point at different bytes. That is
  # what makes "which commit is running?" answerable and a rollback trustworthy.
  aws ecr create-repository \
    --repository-name "${ECR_REPOSITORY}" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --tags "Key=PROJECT_NAME,Value=${PROJECT_NAME}" >/dev/null
  aws ecr put-lifecycle-policy --repository-name "${ECR_REPOSITORY}" \
    --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"keep the last 15 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":15},"action":{"type":"expire"}}]}' \
    >/dev/null
fi

if aws ecr describe-images --repository-name "${ECR_REPOSITORY}" \
  --image-ids "imageTag=${IMAGE_TAG}" >/dev/null 2>&1; then
  log "image ${IMAGE_TAG} is already in ECR - not rebuilding"
else
  need docker
  log "building ${IMAGE_URI}"
  aws ecr get-login-password | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
  # Fargate runs x86_64 here; --platform makes an Apple Silicon laptop build for it too.
  docker build --platform linux/amd64 --target runtime -t "${IMAGE_URI}" "${ROOT}/backend"
  log "pushing"
  docker push "${IMAGE_URI}"
fi

# --- where it runs ----------------------------------------------------------

# The account's default VPC is public subnets in every zone, which is all this
# needs. Set VPC_ID and SUBNET_IDS (comma-separated) to use something else.
if [[ -z "${VPC_ID:-}" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text)"
  [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]] \
    || die "no default VPC in ${AWS_REGION} - set VPC_ID and SUBNET_IDS in .env"
fi
if [[ -z "${SUBNET_IDS:-}" ]]; then
  SUBNET_IDS="$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" Name=default-for-az,Values=true \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ',')"
fi
[[ "${SUBNET_IDS}" == *,* ]] || die "need subnets in at least two zones, found: '${SUBNET_IDS}'"

# --- domain and certificate -------------------------------------------------

# Both are looked up, not stored: if a certificate for API_DOMAIN has been
# issued in this region (make cert-backend), HTTPS is switched on.
API_DOMAIN="${API_DOMAIN:-}"
API_DOMAIN="${API_DOMAIN%.}"
CERT_ARN=""
ZONE_ID=""
if [[ -n "${API_DOMAIN}" ]]; then
  CERT_ARN="$(aws acm list-certificates --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?DomainName=='${API_DOMAIN}']|[0].CertificateArn" \
    --output text 2>/dev/null || true)"
  [[ "${CERT_ARN}" == "None" ]] && CERT_ARN=""
  if [[ -z "${CERT_ARN}" ]]; then
    warn "no issued certificate for ${API_DOMAIN} in ${AWS_REGION} - deploying over HTTP only."
    warn "run: make cert-backend   then deploy again to switch HTTPS on"
  fi
  read -r ZONE_ID _ <<<"$(find_hosted_zone "${API_DOMAIN}")" || true
  [[ -n "${ZONE_ID}" ]] && log "DNS for ${API_DOMAIN} will be managed in Route 53 zone ${ZONE_ID}"
fi

# --- which browsers may call the API ---------------------------------------

# The custom domain, plus the CloudFront address if the frontend stack exists.
CORS="${CORS_ORIGINS_OVERRIDE:-}"
if [[ -z "${CORS}" ]]; then
  origins=()
  [[ -n "${APP_DOMAIN:-}" ]] && origins+=("https://${APP_DOMAIN%.}")
  site="$(stack_output "${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}" SiteUrl)"
  [[ -n "${site}" && "${site}" != "None" ]] && origins+=("${site%/}")
  CORS="$(IFS=,; echo "${origins[*]:-}")"
fi
[[ -n "${CORS}" ]] || warn "CORS_ORIGINS is empty - browsers will be refused until APP_DOMAIN is set"

# --- roll it out ------------------------------------------------------------

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "updating ${STACK_NAME} to ${IMAGE_TAG}"
else
  log "first deploy - creating ${STACK_NAME} (the database takes about ten minutes)"
fi

# CloudFormation waits for the ECS service to settle. If the new container never
# passes its health check, the circuit breaker rolls back and this fails loudly.
if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "ImageUri=${IMAGE_URI}" \
    "VpcId=${VPC_ID}" \
    "SubnetIds=${SUBNET_IDS}" \
    "DomainName=${API_DOMAIN}" \
    "CertificateArn=${CERT_ARN}" \
    "HostedZoneId=${ZONE_ID}" \
    "CorsOrigins=${CORS}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  print_failed_events "${STACK_NAME}"
  exit 1
fi

API_URL="$(stack_output "${STACK_NAME}" ApiUrl)"
ALB_DNS="$(stack_output "${STACK_NAME}" LoadBalancerDnsName)"

# --- smoke test -------------------------------------------------------------

# Ask the load balancer directly, so a DNS record that has not propagated yet
# does not look like a broken deploy.
log "checking /health"
if [[ -n "${CERT_ARN}" ]]; then
  PROBE=(curl -fsSk -H "Host: ${API_DOMAIN}" "https://${ALB_DNS}/health")
else
  PROBE=(curl -fsS "http://${ALB_DNS}/health")
fi
ok=0
for _ in $(seq 1 20); do
  if "${PROBE[@]}" >/dev/null 2>&1; then ok=1; break; fi
  sleep 6
done
[[ "${ok}" == 1 ]] || die "the API did not answer /health - see: make logs-backend"

env_set BACKEND_URL "${API_URL}"

echo
echo "  api        ${API_URL}"
echo "  image      ${IMAGE_URI}"
echo "  logs       make logs-backend"
if [[ -n "${API_DOMAIN}" && -z "${ZONE_ID}" ]]; then
  echo
  echo "  DNS is not in Route 53 here. Add this record where ${API_DOMAIN} is hosted:"
  echo
  echo "    name   ${API_DOMAIN}"
  echo "    type   CNAME"
  echo "    value  ${ALB_DNS}"
fi
echo
