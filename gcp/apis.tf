# A new project has every API switched off. Enabling them here makes a fresh project reproducible.
locals {
  services = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.services)

  service = each.key

  # Leave the APIs on when this configuration is destroyed: switching them off can fail
  # and break other things in the project.
  disable_on_destroy = false
}
