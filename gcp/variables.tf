variable "project_id" {
  type        = string
  description = "The permanent, globally unique project ID, for example spry-yourname-2026."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "6-30 characters: lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Cloud Run, Cloud SQL and Artifact Registry live here. The price list of Lab 9 is for us-central1."
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag of the API image in Artifact Registry. scripts/gcp.sh writes the commit SHA into image.auto.tfvars so every deploy is a new revision."
}

variable "app_env" {
  type        = string
  default     = "development"
  description = <<-EOT
    The API's APP_ENV. "development" is the demo mode of this lab: no sign-in on Google Cloud yet
    (Cognito stays on AWS), so the API serves one shared demo user and anyone with the URL can use it.
    Set "production" together with the cognito_* variables once the Cognito app client lists the
    Firebase Hosting URL as a callback; then the API checks the access token on every request.
  EOT

  validation {
    condition     = contains(["development", "production"], var.app_env)
    error_message = "app_env is development or production."
  }
}

variable "cognito_region" {
  type    = string
  default = ""
}

variable "cognito_user_pool_id" {
  type    = string
  default = ""
}

variable "cognito_client_id" {
  type    = string
  default = ""
}

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Shared-core, 0.6 GB: $0.0105 an hour while running."
}

variable "db_running" {
  type        = bool
  default     = true
  description = "false stops the instance (activation policy NEVER): compute billing stops, the 10 GB disk still bills."
}

variable "db_deletion_protection" {
  type        = bool
  default     = false
  description = "Off in this lab so `terraform destroy` works. Turn it on for anything real."
}

variable "max_instances" {
  type        = number
  default     = 2
  description = "Upper limit of Cloud Run instances. It also caps database connections, because db-f1-micro allows few."
}

# ---- keyless CI (Workload Identity Federation) --------------------------------------------

variable "github_repository" {
  type        = string
  default     = "lyanks/SPRY-1"
  description = "owner/name of the repository that may deploy."
}

variable "github_repository_id" {
  type        = string
  default     = ""
  description = "Numeric repository ID (gh api repos/<owner>/<name> --jq .id). Names can be re-registered; IDs cannot. Empty skips the CI identity."
}

variable "github_owner_id" {
  type        = string
  default     = ""
  description = "Numeric ID of the repository owner (gh api users/<owner> --jq .id)."
}
