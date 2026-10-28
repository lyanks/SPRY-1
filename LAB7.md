# Lab 7 - From CloudFormation to Terraform

## Hand-in

| # | Item | Where |
|---|------|-------|
| 1 | The change that replaces the three CloudFormation templates with Terraform in `infra/`, updates the Makefile and README, and adds the ADR | Branch `lab7`, all changes: https://github.com/lyanks/SPRY-1/compare/lab6...lab7 . The commit that removes the three templates: https://github.com/lyanks/SPRY-1/commit/f1f0b35 |
| 2 | HCP Terraform run that finished with "Apply finished", started by a push | Screenshot attached: workspace `spry-dev`, run "Lab 7: tag the parser's log group (a small change to prove the pipeline)", *triggered a run from GitHub*, 0 added, 1 changed, 0 destroyed |
| 3 | `terraform plan` after the migration | below |

### Item 3 - the plan after the migration

```
aws_iam_role_policy.mailer_read_and_send: Refreshing state... [id=spry-report-mailer:read-and-send]
aws_s3_bucket_notification.reports: Refreshing state... [id=spry-reports-818566829750]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

## What was done

- `infra/versions.tf`, `variables.tf`, `outputs.tf`, `auth.tf` (Lab 4), `reports.tf` (Lab 5), `ai.tf` (Lab 6),
  plus `infra/lambda/mailer/index.py` (the mailer's code, formerly inline in the template).
  The backend, the database and the site (course template) stay CloudFormation.
- One HCP Terraform workspace, `spry-dev` (organization `ooad-spry`): Remote execution, working directory `infra`,
  connected to this repository on the branch `lab7`, apply confirmed by me in the UI.
- The Makefile has `infra-*` targets and no `terraform apply`; the old `deploy-auth/-reports/-ai` targets are gone.
  The deploy scripts read `terraform output`. ADR: `docs/adr/0007-terraform.md`.

### The migration (nothing deleted, nothing re-created)

1. `make tf-vars` copied the stacks' parameters into `infra/terraform.tfvars`; `make tf-imports` wrote `infra/imports.tf`.
2. `make cfn-retain` redeployed the three stacks with `DeletionPolicy: Retain` on every resource (25 resources);
   `make cfn-delete` deleted the stacks. The user pool `spry-users`, the reports bucket and the three Lambdas stayed.
3. First run in HCP Terraform: **32 to import, 3 to add, 17 to change, 0 to destroy**, applied. Terraform has 35 resources for
   25 CloudFormation ones because it models things such as the bucket's public-access block, lifecycle and notification as separate resources.
4. Re-created instead of imported: the three Lambda permissions (the old statements have CloudFormation-made ids and stay).
   Safe: a permission only allows an invocation; briefly two statements say the same, nothing is interrupted.
5. `infra/imports.tf` and the three templates were removed in commit `f1f0b35`; the next plans say `No changes`.

### Problems met, and what fixed them

| Problem | Cause | Fix |
|---|---|---|
| The first plan wanted to replace the Cognito app client (new client id would have broken sign-in) | An imported client cannot read `generate_secret` back, so `generate_secret = false` looked like a change that forces replacement | Leave the argument out (no secret is the default) |
| The Google provider showed attributes about to be removed | Cognito adds default URLs and a `username` mapping itself | Wrote them down in `auth.tf` |
| The queues wanted a smaller maximum message size; the schedule input differed | Terraform's default is 256 KiB; `jsonencode` reorders keys | Set 1 MiB; wrote the original input string |
| `make cfn-retain` was refused on `spry-reports` | The stack still held the old database's security group, which no longer exists (the database was rebuilt) | Used the live backend's security group and host as the parameters |
| `DeletionPolicy` was refused on a template | My edit had also added it to two *parameters* | Removed it there; the check counts resources only |
| A permanent difference on the mailer function | The zip embeds file permissions, which differed between my laptop and the Git checkout | `output_file_mode = "0644"` on the `archive_file` |

### Credentials

HCP Terraform reaches AWS with an access key of an IAM user stored as **sensitive** workspace variables, not with dynamic credentials.
The Lab 2 GitHub OIDC stack was already refused by the organization's policy in this account, so creating a second OIDC provider for HCP
Terraform was not an option; this key is a standing secret and has to be rotated.

## Questions from the lab

**Which road runs first when a change needs both (for example a new environment variable for the Lambda)?**
Infrastructure first: HCP Terraform applies the new variable, then the GitHub Actions pipeline deploys the code that reads it. The other
order makes the new code start without its configuration. When the order cannot be guaranteed, the code must tolerate the variable missing.

**Drift (Step 5).** If a 23:00 console fix had changed a setting, the next plan would show it and the next apply would revert it. The team should
make the same change in `infra/*.tf` in a pull request the next morning, before the next apply; from then on the fix lives in Git.
(I did not run the console experiment itself.)

## What I could not check

The files were first written without the AWS provider being available, so every claim above about what plans and applies do comes from
the real runs in this workspace, not from reasoning. `terraform validate`, the plans and the apply all ran on my laptop and in HCP Terraform.
