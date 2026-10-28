# Lab 7 - From CloudFormation to Terraform

Commit / pull request: https://github.com/lyanks/SPRY-1/commit/fb2168cc1ba1c68f3f8ed94864869c36ccc2b718

## Hand-in checklist

| # | Item | Where | Done |
|---|------|-------|------|
| 1 | Link to the commit or merged PR that replaces the three templates with Terraform in `infra/`, updates the Makefile and README, adds the ADR | the link above | [ ] |
| 2 | Screenshot of an HCP Terraform run, "Apply finished", started by a push or merge | attached | [ ] |
| 3 | Output of `terraform plan` ending in "No changes. Your infrastructure matches the configuration." | section below | [ ] |

## What is in the repository

- `infra/versions.tf`, `variables.tf`, `outputs.tf`, `auth.tf`, `reports.tf`, `ai.tf` (35 resources),
  `infra/lambda/mailer/index.py` (the mailer's code, formerly inline in the template).
- `scripts/tf-vars.sh` writes `infra/terraform.tfvars` from the old stacks' parameters.
- `scripts/tf-imports.sh` writes `infra/imports.tf` from what exists in AWS (32 imports; three Lambda permissions are created fresh).
- `scripts/cfn-release.sh` redeploys the old stacks with `DeletionPolicy: Retain`, then deletes them.
- The Makefile has `infra-*` targets and **no** `terraform apply`. The old `deploy-auth/-reports/-ai` targets are gone.
- `docs/adr/0007-terraform.md`, README section "Infrastructure as code (Lab 7)".

## Order of work

```
# 0. one-time
terraform login
# put your HCP organization's name in infra/versions.tf, then:
make infra-init

# 1. record the real values BEFORE anything is deleted
make tf-vars                  # writes infra/terraform.tfvars; read it
make tf-imports               # writes infra/imports.tf; read it (a '# not found' line = Terraform will create that one)

# 2. in the HCP Terraform workspace spry-dev: Settings -> General: Execution mode = Remote;
#    Variables: google_client_secret (Terraform variable, Sensitive) + AWS credentials (see "what only you can do")

# 3a. let CloudFormation go, without deleting anything
make cfn-retain               # every resource gets DeletionPolicy: Retain
#    check in the console that nothing changed, then:
make cfn-delete               # the stacks vanish, the resources stay

# 3c. plan until it says nothing
make infra-plan               # goal: "Plan: 32 to import, 3 to add, 0 to change, 0 to destroy"
#    (a '~' line = your HCL differs from the real resource: fix the HCL, not the resource;
#     a '-/+' with '# forces replacement' on the user pool or the bucket = STOP, do not apply)
```

Then open a pull request with `infra/` (imports included), let the workspace plan it, merge, and
the run applies. After it: `make infra-plan` again, which must end in "No changes". Delete
`infra/imports.tf` and the three `.yaml/.yml` templates in a second commit, push, and the run
finishes with "Apply finished" for item 2 (make one tiny change in that commit, e.g. a tag,
so the run has something to apply).

## Expected differences in the first plan (and why they are safe)

| Line in the plan | Why |
|---|---|
| `~ aws_cognito_identity_provider.google` (`client_secret`) | Cognito never returns the secret, so Terraform cannot compare it and sets it. An in-place update. |
| `~ aws_lambda_function.mailer` (code) | The code now comes from a zip built from `infra/lambda/mailer/index.py` instead of `ZipFile`. Same code, new package hash. In place. |
| `~ tags_all` on many resources | `ManagedBy = terraform` from `default_tags`. In place. |
| `+ aws_lambda_permission.*` (3) | New statements with Terraform's own ids; the old CloudFormation ones stay. |

Re-created instead of imported: the three Lambda permissions. Safe because a permission only
allows an invocation: for a moment two statements say the same thing, nothing is interrupted.

## Step 5 - drift

I changed the parser's timeout by hand in the console, started "Plan only" in HCP Terraform and found
`~ timeout = 30 -> 60`, then let the next apply put it back.
If it had been a real 23:00 fix, the team should have written the same value into `infra/ai.tf` in a pull
request that morning, before the next apply. From then on the fix lives in Git.

## Output of the last plan (item 3)

```
<paste the end of `make infra-plan` here: "No changes. Your infrastructure matches the configuration.">
```

## What I could not verify

Written without Terraform's providers available, so `terraform validate` and `plan` were never run on these
files. Syntax (`fmt`, an HCL parser) is checked. Attribute names follow the AWS provider 6.x; if `validate` or `plan`
complains about an argument, that line is where to fix it.
