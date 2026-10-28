#!/usr/bin/env bash
# Lab 7, Part 2 Step 3: write infra/terraform.tfvars from the parameters the three
# CloudFormation stacks were deployed with, so the Terraform values equal the real ones
# (a different value would show up as a change in the plan).
#
# Run it BEFORE make cfn-delete. Secrets are not copied: google_client_secret goes into the
# HCP Terraform workspace as a sensitive variable.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
need aws python3
need_credentials

OUT="${ROOT}/infra/terraform.tfvars"
export OUT
AUTH="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
REPORTS="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
AI="${AI_STACK_NAME:-${PROJECT_NAME}-ai}"
BACKEND="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
export PROJECT_NAME AWS_REGION AUTH REPORTS AI BACKEND
python3 - <<'PY'
import json, os, subprocess

def params(stack):
    out = subprocess.run(
        ["aws", "cloudformation", "describe-stacks", "--stack-name", stack,
         "--query", "Stacks[0].Parameters", "--output", "json"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        print(f"warning: no stack {stack}; its values are left out", flush=True)
        return {}
    return {p["ParameterKey"]: p["ParameterValue"] for p in json.loads(out.stdout) or []}

def outputs(stack):
    out = subprocess.run(
        ["aws", "cloudformation", "describe-stacks", "--stack-name", stack,
         "--query", "Stacks[0].Outputs", "--output", "json"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        return {}
    return {o["OutputKey"]: o["OutputValue"] for o in json.loads(out.stdout) or []}

csv = lambda v: [x for x in v.split(",") if x]

values = {"project_name": os.environ["PROJECT_NAME"], "region": os.environ["AWS_REGION"]}
auth, reports, ai = params(os.environ["AUTH"]), params(os.environ["REPORTS"]), params(os.environ["AI"])

if auth:
    values["site_url"] = auth["SiteUrl"]
    values["google_client_id"] = auth["GoogleClientId"]
if reports:
    values.update(
        image_uri=reports["ImageUri"],
        vpc_id=reports["VpcId"],
        subnet_ids=csv(reports["SubnetIds"]),
        route_table_ids=csv(reports["RouteTableIds"]),
        database_security_group_id=reports["DatabaseSecurityGroupId"],
        database_host=reports["DatabaseHost"],
        report_email=reports["ReportEmail"],
        schedule_expression=reports["ScheduleExpression"],
        fail_week=reports["FailWeek"],
    )
# The database may have been rebuilt since the reports stack was deployed: its stored
# parameters would then point at a database that no longer exists. Prefer the live backend.
backend = outputs(os.environ["BACKEND"])
if reports and backend.get("DatabaseEndpoint"):
    for key, out_key in (("database_host", "DatabaseEndpoint"), ("database_security_group_id", "DatabaseSecurityGroupId")):
        if backend.get(out_key) and values[key] != backend[out_key]:
            print(f"note: {key}: reports stack has {values[key]}, backend now has {backend[out_key]}; using the backend's")
            values[key] = backend[out_key]
if ai:
    values["parser_image_uri"] = ai["ImageUri"]
    values.update(
        allowed_origins=csv(ai["AllowedOrigins"]),
        parser_model=ai["ParserModel"],
        parser_api=ai["ParserApi"],
        parser_effort=ai["ParserEffort"],
        bedrock_region=ai["BedrockRegion"],
    )

with open(os.environ["OUT"], "w") as f:
    f.write("# Non-secret values, copied from the CloudFormation stacks by scripts/tf-vars.sh.\n")
    f.write("# google_client_secret is NOT here: it is a sensitive variable of the HCP Terraform workspace.\n")
    for k, v in values.items():
        f.write(f"{k} = {json.dumps(v)}\n")
print("wrote", os.environ["OUT"])
PY
