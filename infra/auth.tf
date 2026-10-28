# Spry sign-in (Lab 4): a Cognito user pool with managed login, so the site can
# sign people in with an email and password or with a Google account.
# Was infra/auth.yaml.

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Managed login needs Essentials; the first 10,000 monthly users are free.
  user_pool_tier = "ESSENTIALS"

  # People sign in with their email, not a separate username.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    # Self sign-up stays on, so the lecturer can create their own account.
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  deletion_protection = "INACTIVE"

  # Every account that signed up lives in this pool. Changing an attribute that
  # forces a new pool (read the plan for "# forces replacement") would delete
  # them. This makes Terraform refuse instead. Remove these three lines only
  # for the final clean-up.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "openid email profile"
  }

  # Without the mapping a Google user arrives with no email, and the header
  # would have nothing to show.
  attribute_mapping = {
    username       = "sub"
    email          = "email"
    email_verified = "email_verified"
  }
}

# A public client: a browser cannot keep a secret, so it gets none. PKCE (done
# by the OIDC library) protects the code exchange instead.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO", "Google"]
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true

  # Cognito matches these exactly, trailing slash included, so both spellings
  # are listed. localhost is for `docker compose up`.
  callback_urls = [
    "${var.site_url}/auth/callback",
    "${var.site_url}/auth/callback/",
    "http://localhost:3000/auth/callback",
    "http://localhost:3000/auth/callback/",
  ]
  logout_urls = [
    "${var.site_url}/",
    "http://localhost:3000/",
  ]

  # A client that names a provider which does not exist yet fails to create.
  depends_on = [aws_cognito_identity_provider.google]
}

# The prefix is built from the account id, so it is unique, stable, and known
# before the first deploy, which Google's console needs.
resource "aws_cognito_user_pool_domain" "main" {
  domain                = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

# Without branding, a version 2 domain has no sign-in page to show.
resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  client_id    = aws_cognito_user_pool_client.web.id

  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.main]
}
