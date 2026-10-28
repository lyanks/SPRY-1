#!/usr/bin/env bash
# Build the backend's Lambda image, push it to ECR and print its URI.
# Terraform does not build images: give it the URI as the workspace variable image_uri
# (the report builder and the agenda parser use the same image).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
need aws git docker
need_credentials

ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"
TAG="lambda-$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
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

echo
echo "image_uri = \"${IMAGE_URI}\""
echo "Set it as image_uri (report builder) or parser_image_uri (agenda parser) in infra/terraform.tfvars."
