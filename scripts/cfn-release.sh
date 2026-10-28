#!/usr/bin/env bash
# Lab 7, Part 2 Step 3a: let CloudFormation go without deleting anything.
#
#   scripts/cfn-release.sh retain   redeploy the three stacks with DeletionPolicy: Retain on every
#                                   resource (the templates in infra/ already say so); parameters are kept
#   scripts/cfn-release.sh delete   delete the stacks, after checking each deployed template says Retain
#                                   everywhere. The resources stay, owned by nobody (until terraform apply).
#
# Do this only after `make tf-imports` has written infra/imports.tf and you have looked at it.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
need aws
need_credentials

MODE="${1:-}"
# stack name -> template file
declare -A STACKS=(
  ["${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"]="auth.yaml"
  ["${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"]="reports.yaml"
  ["${AI_STACK_NAME:-${PROJECT_NAME}-ai}"]="ai.yml"
)

exists() { aws cloudformation describe-stacks --stack-name "$1" >/dev/null 2>&1; }

case "${MODE}" in
  retain)
    for stack in "${!STACKS[@]}"; do
      if ! exists "${stack}"; then warn "${stack}: no such stack, skipping"; continue; fi
      template="${ROOT}/infra/${STACKS[$stack]}"
      params=()
      for key in $(aws cloudformation describe-stacks --stack-name "${stack}" \
        --query 'Stacks[0].Parameters[].ParameterKey' --output text); do
        value=""
        # The database was rebuilt after the reports stack was deployed: its stored security
        # group no longer exists and CloudFormation refuses to update with it. Use the live ones.
        if [[ "${STACKS[$stack]}" == "reports.yaml" ]]; then
          backend="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
          case "${key}" in
            DatabaseSecurityGroupId) value="$(stack_output "${backend}" DatabaseSecurityGroupId)" ;;
            DatabaseHost) value="$(stack_output "${backend}" DatabaseEndpoint)" ;;
          esac
          [[ "${value}" != "None" ]] || value=""
        fi
        if [[ -n "${value}" ]]; then
          log "${stack}: ${key} = ${value} (from ${backend})"
          params+=("ParameterKey=${key},ParameterValue=${value}")
        else
          params+=("ParameterKey=${key},UsePreviousValue=true")
        fi
      done
      log "${stack}: redeploying ${STACKS[$stack]} with Retain"
      if out="$(aws cloudformation update-stack --stack-name "${stack}" \
        --template-body "file://${template}" --capabilities CAPABILITY_NAMED_IAM \
        ${params[@]:+--parameters "${params[@]}"} 2>&1)"; then
        aws cloudformation wait stack-update-complete --stack-name "${stack}"
        log "${stack}: updated"
      elif grep -q "No updates are to be performed" <<<"${out}"; then
        log "${stack}: already up to date"
      else
        warn "${stack}: ${out}"
        print_failed_events "${stack}" || true
        die "stopped at ${stack}; nothing has been deleted"
      fi
    done
    echo
    echo "Next: make cfn-delete"
    ;;

  delete)
    for stack in "${!STACKS[@]}"; do
      if ! exists "${stack}"; then warn "${stack}: no such stack, skipping"; continue; fi
      body="$(aws cloudformation get-template --stack-name "${stack}" --query TemplateBody --output text)"
      resources="$(awk '/^Resources:/{r=1;next} /^[A-Za-z]/{r=0} r' <<<"${body}")"
      total="$(grep -cE '^    Type: AWS::' <<<"${resources}" || true)"
      kept="$(grep -c 'DeletionPolicy: Retain' <<<"${resources}" || true)"
      [[ "${total}" -gt 0 && "${kept}" -ge "${total}" ]] \
        || die "${stack}: only ${kept} of ${total} resources say DeletionPolicy: Retain. Run make cfn-retain first. Nothing deleted."
    done
    for stack in "${!STACKS[@]}"; do
      exists "${stack}" || continue
      log "${stack}: deleting the stack (its resources stay)"
      aws cloudformation delete-stack --stack-name "${stack}"
      aws cloudformation wait stack-delete-complete --stack-name "${stack}"
    done
    echo
    echo "The stacks are gone; check in the console that the user pool, the bucket and the functions are still there."
    echo "Next: make infra-plan   (goal: 'N to import, 0 to add, 0 to change, 0 to destroy')"
    ;;

  *) echo "usage: $0 retain | delete" >&2; exit 2 ;;
esac
