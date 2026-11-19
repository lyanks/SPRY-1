terraform {
  required_version = ">= 1.10"

  # State lives in a second HCP Terraform workspace, separate from the AWS one (spry-dev), so one
  # plan cannot break both clouds. Create it with Execution Mode = Local: Terraform then runs on
  # your laptop with your gcloud credentials, and HCP only stores and locks the state. No Google
  # key is stored anywhere. (For remote runs, give the workspace Workload Identity Federation.)
  cloud {
    organization = "ooad-spry"

    workspaces {
      name = "spry-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Credentials: your own account through `gcloud auth application-default login`
# (locally), or Workload Identity Federation (CI, see ci.tf). Never a JSON key.
provider "google" {
  project = var.project_id
  region  = var.region
}
