# Everything the Makefile, the scripts and the frontend build read.
# `terraform -chdir=infra output -raw <name>`

# ---- auth --------------------------------------------------------------------

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "authority" {
  description = "The OIDC issuer; the frontend's `authority`."
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "cognito_domain" {
  description = "Cognito's hosted domain; also where /logout lives."
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "The 'Authorised redirect URI' Google's OAuth client must list."
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}

output "login_url" {
  value = "${var.site_url}/login/"
}

# ---- reports -----------------------------------------------------------------

output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "report_queue_url" {
  value = aws_sqs_queue.requests.url
}

output "report_dead_letter_queue_url" {
  value = aws_sqs_queue.dead_letter.url
}

# ---- ai ----------------------------------------------------------------------

output "parser_url" {
  description = "Compiled into the frontend as NEXT_PUBLIC_PARSER_URL."
  value       = aws_lambda_function_url.parser.function_url
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}
