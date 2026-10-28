# Spry "Paste an agenda" (Lab 6). One Lambda function, outside the VPC, behind a
# function URL: the browser sends pasted text, the function asks Claude on Amazon
# Bedrock to fill in a validated record_agenda tool call, and returns JSON. It
# needs no database and writes nothing. Was infra/ai.yml.
#
# The $5 AWS Budgets alarm is still created by scripts/ai.sh (make ai-budget).

resource "aws_iam_role" "parser" {
  name = "${var.project_name}-agenda-parser"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parser_logs" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# "*" for now, as in Lab 6: which models and regions this may reach is a
# discussion question (docs/adr/0006). InvokeModel is the bedrock-runtime route;
# CreateInference is the Mantle route.
resource "aws_iam_role_policy" "parser_call_claude" {
  name = "call-claude"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock-mantle:CreateInference"]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 30

  tags = {
    Lab = "7"
  }
}

# No vpc_config: the function needs no database, and outside a VPC it reaches
# Bedrock and Cognito's keys over the internet with no NAT and no endpoint.
resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  package_type  = "Image"
  image_uri     = var.parser_image_uri
  role          = aws_iam_role.parser.arn
  timeout       = 60 # a model call may take 20 s and the SDK retries twice
  memory_size   = 512

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      PARSER_EFFORT        = var.parser_effort
      PARSER_API           = var.parser_api
      BEDROCK_REGION       = var.bedrock_region
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      APP_ENV              = "production"
    }
  }

  depends_on = [aws_cloudwatch_log_group.parser, aws_iam_role_policy_attachment.parser_logs]
}

resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE" # the handler verifies the Cognito token itself

  cors {
    allow_origins = var.allowed_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# A public function URL needs both statements, or callers get 403.
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "AllowFunctionUrl"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_invoke" {
  statement_id             = "AllowInvokeViaFunctionUrl"
  function_name            = aws_lambda_function.parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}
