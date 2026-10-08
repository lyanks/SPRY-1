# shellcheck shell=bash
# Helpers shared by the backend deploy scripts. Source it, do not run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # Variables already exported win over .env: `AWS_REGION=eu-west-1 make x`
    # must not be quietly reset to the region .env names.
    local preset
    preset="$(export -p)"
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
    eval "${preset}"
  fi

  # A blank AWS_PROFILE is read as a profile literally named "", and blank keys
  # short-circuit the credential chain. Treat empty as absent.
  local var
  for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
    [[ -n "${!var:-}" ]] || unset "${var}"
  done

  PROJECT_NAME="${PROJECT_NAME:-spry}"
  AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}"
  export AWS_DEFAULT_REGION="${AWS_REGION}"
}

need() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
  done
}

need_credentials() {
  aws sts get-caller-identity >/dev/null 2>&1 \
    || die "no usable AWS credentials - set AWS_PROFILE (or SSO login), or the AWS_* keys in your shell"
}

# Rewrite one KEY=VALUE in .env, leaving every other line exactly as it was.
# Skipped on CI, where there is no .env and nothing should be written.
env_set() {
  [[ -z "${CI:-}" ]] || return 0
  KEY="$1" VALUE="$2" ENV_FILE="${ENV_FILE}" python3 - <<'PY'
import os, re

key, value, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pattern = re.compile(rf"^{re.escape(key)}=")

for i, line in enumerate(lines):
    if pattern.match(line):
        lines[i] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")

open(path, "w").write("\n".join(lines) + "\n")
PY
  log "wrote ${1} to .env"
}

# The zone for api.example.com is example.com: keep the longest public zone the
# domain sits under. Prints "<zone id> <zone name>", or nothing.
find_hosted_zone() {
  DOMAIN="$1" python3 - <<'PY'
import json, os, subprocess

domain = os.environ["DOMAIN"]
out = subprocess.run(
    ["aws", "route53", "list-hosted-zones", "--output", "json"],
    capture_output=True, text=True,
)
if out.returncode != 0:
    raise SystemExit(0)

best = None
for zone in json.loads(out.stdout).get("HostedZones", []):
    if zone.get("Config", {}).get("PrivateZone"):
        continue
    name = zone["Name"].rstrip(".")
    if domain == name or domain.endswith("." + name):
        if best is None or len(name) > len(best[1]):
            best = (zone["Id"].split("/")[-1], name)

if best:
    print(best[0], best[1])
PY
}

print_failed_events() {
  warn "deploy failed - most recent failure reasons:"
  # shellcheck disable=SC2016 # backticks are JMESPath literals, not shell
  aws cloudformation describe-stack-events --stack-name "$1" \
    --max-items 40 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" \
    --output text 2>/dev/null || true
}
