output "api_url" {
  description = "The Cloud Run URL of the API."
  value       = google_cloud_run_v2_service.api.uri
}

output "site_url" {
  description = "Firebase Hosting serves the static frontend here (deployed by scripts/gcp.sh frontend)."
  value       = "https://${var.project_id}.web.app"
}

output "database_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "image_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.spry.repository_id}"
}

output "ci_workload_identity_provider" {
  description = "Goes into the google-github-actions/auth step as workload_identity_provider."
  value       = local.ci_enabled ? google_iam_workload_identity_pool_provider.github[0].name : ""
}

output "ci_service_account" {
  value = local.ci_enabled ? google_service_account.deployer[0].email : ""
}
