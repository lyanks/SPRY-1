#!/usr/bin/env bash
# Lab 9: Spry's core on Google Cloud. Run one phase at a time from the project root:
#   bash scripts/gcp.sh check       are gcloud, Terraform, Docker, billing and credentials in order?
#   bash scripts/gcp.sh bootstrap   terraform init; enable the APIs; create the image registry
#   bash scripts/gcp.sh image       build the API image (linux/amd64) and push it to Artifact Registry
#   bash scripts/gcp.sh apply       terraform apply: Cloud SQL, secret, service account, Cloud Run
#   bash scripts/gcp.sh frontend    static export -> Firebase Hosting (rewrites /api/** to Cloud Run)
#   bash scripts/gcp.sh smoke       calls the deployed API and site
#   bash scripts/gcp.sh db-stop     stop Cloud SQL (compute stops billing; the disk still bills)
#   bash scripts/gcp.sh db-start    start it again
#   bash scripts/gcp.sh destroy     terraform destroy: everything this lab created
#   bash scripts/gcp.sh up          bootstrap + image + apply + frontend + smoke
# The project ID comes from GCP_PROJECT_ID (environment or .env).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GCP="${ROOT}/gcp"
cd "${ROOT}"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { for t in "$@"; do command -v "${t}" >/dev/null 2>&1 || die "${t} is required but not installed"; done; }

# GCP_PROJECT_ID: the environment wins over .env
PROJECT="${GCP_PROJECT_ID:-}"
if [[ -z "${PROJECT}" && -f .env ]]; then
  PROJECT="$(grep -E '^GCP_PROJECT_ID=' .env | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
fi
[[ -n "${PROJECT}" ]] || die "set GCP_PROJECT_ID (in .env or the environment), for example GCP_PROJECT_ID=spry-yourname-2026"
REGION="${GCP_REGION:-us-central1}"
export TF_VAR_project_id="${PROJECT}"
export TF_VAR_region="${REGION}"
export CLOUDSDK_CORE_PROJECT="${PROJECT}"

tf() { terraform -chdir="${GCP}" "$@"; }
tf_out() { tf output -raw "$1" 2>/dev/null || true; }
fb() { (cd "${GCP}/firebase" && npx --yes firebase-tools@14 "$@"); }

tag() { git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || date +%Y%m%d%H%M%S; }

github_ids() {
  # Numeric IDs for the Workload Identity condition. Skipped quietly if GitHub cannot be reached.
  local repo="${GITHUB_REPOSITORY:-lyanks/SPRY-1}" owner rid oid
  owner="${repo%%/*}"
  if command -v gh >/dev/null 2>&1; then
    rid="$(gh api "repos/${repo}" --jq .id 2>/dev/null || true)"
    oid="$(gh api "users/${owner}" --jq .id 2>/dev/null || true)"
  fi
  if [[ -z "${rid:-}" ]]; then
    rid="$(curl -fsS "https://api.github.com/repos/${repo}" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
    oid="$(curl -fsS "https://api.github.com/users/${owner}" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
  fi
  if [[ -n "${rid:-}" && -n "${oid:-}" ]]; then
    printf 'github_repository    = "%s"\ngithub_repository_id = "%s"\ngithub_owner_id      = "%s"\n' "${repo}" "${rid}" "${oid}" > "${GCP}/ids.auto.tfvars"
    log "GitHub IDs for ${repo}: repository ${rid}, owner ${oid}"
  else
    warn "could not read the numeric GitHub IDs; the keyless CI identity is skipped (set github_repository_id / github_owner_id)"
  fi
}

case "${1:-}" in
  check)
    need gcloud terraform docker node
    log "account:  $(gcloud config get-value account 2>/dev/null)"
    log "project:  ${PROJECT}"
    gcloud projects describe "${PROJECT}" --format='value(projectId,lifecycleState)' >/dev/null 2>&1 \
      || die "gcloud cannot see project ${PROJECT}: create it in the console and run: gcloud auth login"
    BILLING="$(gcloud billing projects describe "${PROJECT}" --format='value(billingEnabled)' 2>/dev/null || true)"
    [[ "${BILLING}" == "True" ]] || die "billing is not enabled for ${PROJECT} (link the free-trial billing account in the console)"
    gcloud auth application-default print-access-token >/dev/null 2>&1 \
      || die "no application default credentials: run  gcloud auth application-default login"
    if npx --yes firebase-tools@14 login:list 2>/dev/null | grep -qi "no authorized accounts"; then
      warn "Firebase CLI is not signed in: run  npx firebase-tools@14 login   (needed for the frontend step only)"
    fi
    log "all good"
    ;;
  bootstrap)
    need terraform
    github_ids
    tf init -input=false
    log "enabling the APIs and creating the registry"
    tf apply -input=false -auto-approve \
      -target=google_project_service.enabled \
      -target=google_artifact_registry_repository.spry
    ;;
  image)
    need docker
    T="$(tag)"
    REPO="${REGION}-docker.pkg.dev/${PROJECT}/spry"
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    log "building ${REPO}/api:${T} (the 'runtime' stage; the Lambda stage is for AWS)"
    docker build --platform linux/amd64 --target runtime -t "${REPO}/api:${T}" backend
    docker push "${REPO}/api:${T}"
    printf 'image_tag = "%s"\n' "${T}" > "${GCP}/image.auto.tfvars"
    log "image ${T} pushed; written to gcp/image.auto.tfvars"
    ;;
  apply)
    need terraform
    [[ -f "${GCP}/image.auto.tfvars" ]] || die "no image yet: run  bash scripts/gcp.sh image"
    tf init -input=false
    tf apply -input=false "${@:2}"
    echo; echo "  api   $(tf_out api_url)"; echo "  site  $(tf_out site_url)"
    ;;
  frontend)
    need node npx
    API="$(tf_out api_url)"
    [[ -n "${API}" ]] || die "no API yet: run  bash scripts/gcp.sh apply"
    if command -v pnpm >/dev/null 2>&1; then PM=(pnpm); elif command -v corepack >/dev/null 2>&1; then PM=(corepack pnpm); else PM=(npx --yes pnpm@10); fi
    log "building the static export; the API is reached on the site's own origin (Firebase rewrites /api/** to Cloud Run)"
    (cd frontend && "${PM[@]}" install --frozen-lockfile)
    rm -rf frontend/out
    # An empty API URL makes every request relative: /api/meetings on the same origin, so no CORS.
    # No Cognito variables: sign-in stays on AWS in this lab (see ADR 0008).
    (cd frontend && env NEXT_OUTPUT=export NEXT_PUBLIC_API_URL="" "${PM[@]}" build)
    [[ -f frontend/out/index.html ]] || die "the export produced no frontend/out/index.html"
    # the rewrite regions in firebase.json must match the region of the service
    sed -i.bak "s/\"region\": \"[a-z0-9-]*\"/\"region\": \"${REGION}\"/g" "${GCP}/firebase/firebase.json" && rm -f "${GCP}/firebase/firebase.json.bak"
    if ! fb hosting:sites:list --project "${PROJECT}" 2>/dev/null | grep -q "${PROJECT}"; then
      log "adding Firebase to the project and creating the default Hosting site"
      fb projects:addfirebase "${PROJECT}" || true
      fb hosting:sites:create "${PROJECT}" --project "${PROJECT}" || true
    fi
    fb deploy --only hosting --project "${PROJECT}"
    echo; echo "  site  https://${PROJECT}.web.app"
    ;;
  smoke)
    API="$(tf_out api_url)"; SITE="https://${PROJECT}.web.app"
    [[ -n "${API}" ]] || die "no API yet"
    log "GET ${API}/health"; curl -fsS "${API}/health"; echo
    log "GET ${API}/health/ready   (a SELECT 1 on Cloud SQL)"; curl -fsS "${API}/health/ready"; echo
    log "GET ${SITE}/health/ready   (through Firebase Hosting -> Cloud Run)"; curl -fsS "${SITE}/health/ready"; echo
    log "POST ${SITE}/api/meetings  (writes a row)"
    curl -fsS -X POST "${SITE}/api/meetings" -H 'Content-Type: application/json' \
      -d '{"title":"Lab 9 demo","starts_at":"2026-11-16T10:00:00Z","ends_at":"2026-11-16T10:30:00Z","attendee_count":3,"agenda":null}' || warn "POST failed (a signed-in production API needs a token)"
    echo; log "GET ${SITE}/api/meetings   (reads the rows back from Cloud SQL)"
    curl -fsS "${SITE}/api/meetings"; echo
    ;;
  db-stop)
    tf apply -input=false -auto-approve -var db_running=false
    ;;
  db-start)
    tf apply -input=false -auto-approve -var db_running=true
    ;;
  destroy)
    need terraform
    warn "this deletes Cloud SQL (and its data), Cloud Run, the registry and the secret in ${PROJECT}"
    read -r -p "type the project ID to confirm: " ans
    [[ "${ans}" == "${PROJECT}" ]] || die "not confirmed"
    tf destroy -input=false -auto-approve
    log "Firebase Hosting is not in Terraform: run  npx firebase-tools@14 hosting:disable --project ${PROJECT}  to take the site down"
    ;;
  up)
    "$0" bootstrap; "$0" image; "$0" apply -auto-approve; "$0" frontend; "$0" smoke
    ;;
  *)
    sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
