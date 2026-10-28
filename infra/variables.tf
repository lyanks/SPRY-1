# ---- common -----------------------------------------------------------------

variable "project_name" {
  type    = string
  default = "spry"
}

variable "region" {
  type        = string
  default     = "eu-north-1"
  description = "Where the stacks of Labs 4-6 live."
}

# ---- auth (Lab 4) -----------------------------------------------------------

variable "site_url" {
  type        = string
  description = "The site's origin without a trailing slash. Cognito only returns the browser to URLs listed here."

  validation {
    condition     = can(regex("^https://[^/]+$", var.site_url))
    error_message = "site_url must look like https://xxxx.cloudfront.net (no trailing slash)."
  }
}

variable "google_client_id" {
  type        = string
  description = "The OAuth client ID of the Google 'Web application' client."
}

variable "google_client_secret" {
  type        = string
  sensitive   = true
  description = "The matching client secret. Set it as a sensitive variable in the HCP Terraform workspace, never in a file."
}

# ---- reports (Lab 5) --------------------------------------------------------

variable "image_uri" {
  type        = string
  description = "The Lambda-target image of the backend in ECR that the report builder runs."
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route tables of those subnets; the S3 gateway endpoint is attached to them."
}

variable "database_security_group_id" {
  type = string
}

variable "database_host" {
  type = string
}

variable "report_email" {
  type        = string
  description = "A verified SES identity, used as sender and recipient."
}

variable "schedule_expression" {
  type    = string
  default = "cron(0 7 ? * MON *)"
}

variable "fail_week" {
  type        = string
  default     = ""
  description = "An ISO week for which the builder raises on purpose (Lab 5, Step 7). Empty = never."
}

# ---- ai (Lab 6) -------------------------------------------------------------

variable "parser_image_uri" {
  type        = string
  description = "The Lambda-target image the agenda parser runs. A different tag from image_uri: the parser's code is newer than the report builder's."
}

variable "allowed_origins" {
  type        = list(string)
  description = "Origins that may call the parser's function URL from a browser."
}

variable "parser_model" {
  type    = string
  default = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "parser_api" {
  type    = string
  default = "runtime"

  validation {
    condition     = contains(["runtime", "mantle"], var.parser_api)
    error_message = "parser_api must be runtime or mantle."
  }
}

variable "parser_effort" {
  type    = string
  default = ""
}

variable "bedrock_region" {
  type    = string
  default = "us-east-1"
}
