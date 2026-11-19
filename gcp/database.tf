# Cloud SQL for PostgreSQL, the smallest shared-core tier. UNLIKE Aurora it never pauses by itself:
# it bills every hour it runs. `db_running = false` is the off switch.
resource "google_sql_database_instance" "main" {
  name             = "spry-db"
  database_version = "POSTGRES_16"
  region           = var.region

  deletion_protection = var.db_deletion_protection

  settings {
    tier = var.db_tier
    # Shared-core machine types exist only in the Enterprise edition.
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"

    disk_type       = "PD_SSD"
    disk_size       = 10
    disk_autoresize = false

    activation_policy           = var.db_running ? "ALWAYS" : "NEVER"
    deletion_protection_enabled = var.db_deletion_protection

    # Cloud Run reaches the instance through the Cloud SQL connector (a unix socket, IAM-authorised),
    # so no authorized network is needed: the public address is closed to everyone else.
    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false # a lab database; turn backups on for real data
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_sql_database" "spry" {
  name     = "spry"
  instance = google_sql_database_instance.main.name
}

# Generated here, stored in Secret Manager, never in the repository. (It is also in the Terraform
# state, which is why the state is as secret as the password.)
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_sql_user" "spry" {
  name     = "spry"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "spry-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}
