# Where the backend image lives. 0.5 GB is free; one image of this backend is a few hundred MB.
resource "google_artifact_registry_repository" "spry" {
  repository_id = "spry"
  location      = var.region
  format        = "DOCKER"
  description   = "Spry backend images"

  depends_on = [google_project_service.enabled]
}

locals {
  api_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.spry.repository_id}/api:${var.image_tag}"
}
