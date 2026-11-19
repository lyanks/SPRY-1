# The identity the API runs as. One service account per program; not the default compute account,
# which starts with the Editor role.
resource "google_service_account" "api" {
  account_id   = "spry-api"
  display_name = "Spry API (Cloud Run)"

  depends_on = [google_project_service.enabled]
}

resource "google_project_iam_member" "api_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Only this one secret, not every secret in the project.
resource "google_secret_manager_secret_iam_member" "api_db_password" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

locals {
  hosting_origins = [
    "https://${var.project_id}.web.app",
    "https://${var.project_id}.firebaseapp.com",
  ]

  # Sign-in settings are passed only when all of them are set.
  cognito_env = (
    var.cognito_region != "" && var.cognito_user_pool_id != "" && var.cognito_client_id != ""
    ? {
      COGNITO_REGION       = var.cognito_region
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
      COGNITO_CLIENT_ID    = var.cognito_client_id
    }
    : {}
  )
}

resource "google_cloud_run_v2_service" "api" {
  name     = "spry-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    # Scale to zero: an idle API costs nothing. The cap also bounds database connections.
    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = local.api_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # request-based billing: CPU is charged only while a request runs
        startup_cpu_boost = true
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "APP_ENV"
        value = var.app_env
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", local.hosting_origins)
      }
      # The entrypoint builds DATABASE_URL from these (a unix socket when DB_HOST starts with "/").
      env {
        name  = "DB_HOST"
        value = "/cloudsql/${google_sql_database_instance.main.connection_name}"
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.spry.name
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.spry.name
      }
      # db-f1-micro allows few connections and instances come and go: one connection per request.
      env {
        name  = "DB_POOLING"
        value = "false"
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      dynamic "env" {
        for_each = local.cognito_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # The container applies the migrations before it listens, so allow a long start (<= 240 s).
      startup_probe {
        http_get {
          path = "/health"
        }
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 40
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.api_db_password,
    google_project_iam_member.api_cloudsql,
    google_sql_user.spry,
  ]
}

# The API is public. In production mode it checks tokens itself, which is why it may be open
# to the internet: the same reason the Lambda function URL was open in Lab 6.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
