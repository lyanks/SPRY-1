# Keyless CI: GitHub Actions presents a short-lived OIDC token, Google swaps it for a short-lived
# token of the service account below. No JSON key exists. Same idea as the AWS role of Lab 4 / 7.
# Skipped until github_repository_id and github_owner_id are set (scripts/gcp.sh sets them).
locals {
  ci_enabled = var.github_repository_id != "" && var.github_owner_id != ""

  # What this configuration needs in order to deploy itself. Not Owner, not Editor.
  deployer_roles = [
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.serviceAccountUser",
    # Because Terraform here also creates a service account and its bindings:
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/firebasehosting.admin",
  ]
}

resource "google_service_account" "deployer" {
  count = local.ci_enabled ? 1 : 0

  account_id   = "spry-terraform"
  display_name = "Spry Terraform / CI deployer"

  depends_on = [google_project_service.enabled]
}

resource "google_project_iam_member" "deployer" {
  for_each = local.ci_enabled ? toset(local.deployer_roles) : toset([])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.deployer[0].email}"
}

resource "google_iam_workload_identity_pool" "github" {
  count = local.ci_enabled ? 1 : 0

  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count = local.ci_enabled ? 1 : 0

  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }

  # Only this repository, by numeric ID: a name can be re-registered by someone else after a rename.
  attribute_condition = "assertion.repository_id == \"${var.github_repository_id}\" && assertion.repository_owner_id == \"${var.github_owner_id}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_can_impersonate" {
  count = local.ci_enabled ? 1 : 0

  service_account_id = google_service_account.deployer[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository_id/${var.github_repository_id}"
}
