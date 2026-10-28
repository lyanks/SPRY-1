# Spry weekly report, event-driven (Lab 5). EventBridge Scheduler and
# `make report-now` put a command on SQS; the report-builder Lambda (in the VPC,
# backend image) reads the database and writes reports/<week>.csv to S3 through
# a gateway endpoint; that file is an event that starts the report-mailer Lambda
# (outside the VPC), which sends it through SES. Neither function calls the other.
# Was infra/reports.yaml.

locals {
  reports_bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
}

# ---- storage -----------------------------------------------------------------

# In CloudFormation the bucket's notification, the invoke permission and the
# bucket itself formed a circle, and a constructed name was the way out. Here
# they are three resources, and the circle is gone.
resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket

  # Every report ever built is in here. Remove only for the final clean-up.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-after-90-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_from_s3]
}

resource "aws_lambda_permission" "mailer_from_s3" {
  statement_id   = "AllowReportsBucket"
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_s3_bucket.reports.arn
}

# Free. Without it the builder's PutObject hangs until the timeout: the VPC has
# no NAT and the request has nowhere to go.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = var.route_table_ids
}

# ---- queue -------------------------------------------------------------------

resource "aws_sqs_queue" "dead_letter" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600
  max_message_size          = 1048576
}

resource "aws_sqs_queue" "requests" {
  name             = "${var.project_name}-report-requests"
  max_message_size = 1048576

  # 6 x the builder's 60 s timeout: if the message became visible again while
  # the first attempt still ran, a second builder would start on the same report.
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = 3
  })
}

# ---- trigger 1: the schedule (a command onto the queue) ----------------------

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-report-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_send_to_queue" {
  name = "send-to-queue"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name                         = "${var.project_name}-weekly-report"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Europe/Kyiv"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.requests.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{\"week\": null, \"source\": \"schedule\"}"
  }
}

# ---- trigger 2: the SQS message -> the builder -------------------------------

resource "aws_security_group" "builder" {
  description = "report-builder Lambda"
  vpc_id      = var.vpc_id

  # Terraform removes the "allow all outbound" rule that AWS adds to a new
  # security group, so it is written down. (CloudFormation kept the default.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The database's security group belongs to the backend stack; only this one
# rule is ours.
resource "aws_vpc_security_group_ingress_rule" "database_from_builder" {
  security_group_id            = var.database_security_group_id
  referenced_security_group_id = aws_security_group.builder.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "report-builder"
}

resource "aws_iam_role" "builder" {
  name = "${var.project_name}-report-builder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "builder_vpc" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder_reports" {
  name = "reports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.requests.arn
      },
    ]
  })
}

# The backend stack created this secret. Read at apply time, the value ends up
# in the function's configuration (the function sits in a VPC with no NAT, so it
# cannot call Secrets Manager at run time) and, with Terraform, in the state.
data "aws_secretsmanager_secret_version" "database" {
  secret_id = "${var.project_name}/backend/db"
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.builder.arn
  timeout       = 60 # Aurora/RDS may need a moment; SQS visibility is 6x this
  memory_size   = 512

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.builder.id]
  }

  environment {
    variables = {
      REPORTS_BUCKET = local.reports_bucket
      DB_HOST        = var.database_host
      DB_NAME        = "spry"
      DB_USER        = "spry"
      DB_SSL         = "require"
      FAIL_WEEK      = var.fail_week
      DB_PASSWORD    = jsondecode(data.aws_secretsmanager_secret_version.database.secret_string)["password"]
    }
  }

  depends_on = [aws_vpc_endpoint.s3, aws_iam_role_policy_attachment.builder_vpc]
}

resource "aws_lambda_event_source_mapping" "requests" {
  event_source_arn = aws_sqs_queue.requests.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
}

# ---- trigger 3: the file in S3 -> the mailer ---------------------------------

resource "aws_iam_role" "mailer" {
  name = "${var.project_name}-report-mailer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mailer_logs" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer_read_and_send" {
  name = "read-and-send"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = "ses:SendRawEmail"
        Resource = "*"
      },
    ]
  })
}

# The code used to sit inside the template (ZipFile). Now it is a file next to
# the Terraform, zipped at plan time.
data "archive_file" "mailer" {
  type        = "zip"
  source_file = "${path.module}/lambda/mailer/index.py"
  output_path = "${path.module}/.build/mailer.zip"
}

# Not in a VPC: it needs the internet to reach SES, and never touches the
# database. It must never write under reports/ - a function triggered by uploads
# to a prefix that uploads to the same prefix calls itself forever.
resource "aws_lambda_function" "mailer" {
  function_name    = "${var.project_name}-report-mailer"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.mailer.arn
  timeout          = 30
  filename         = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256

  environment {
    variables = {
      SENDER    = var.report_email
      RECIPIENT = var.report_email
    }
  }

  depends_on = [aws_iam_role_policy_attachment.mailer_logs]
}
