# Written by scripts/tf-imports.sh. Delete this file after the migration (Lab 7, Step 3c).

import {
  to = aws_cognito_user_pool.main
  id = "eu-north-1_6q9IeQuFy"
}

import {
  to = aws_cognito_identity_provider.google
  id = "eu-north-1_6q9IeQuFy:Google"
}

import {
  to = aws_cognito_user_pool_client.web
  id = "eu-north-1_6q9IeQuFy/3c52e7357058sp42o99l042b3o"
}

import {
  to = aws_cognito_user_pool_domain.main
  id = "spry-818566829750"
}

import {
  to = aws_cognito_managed_login_branding.main
  id = "eu-north-1_6q9IeQuFy,946461e6-ed83-4553-beb8-d2d7fc1f1626"
}

import {
  to = aws_s3_bucket.reports
  id = "spry-reports-818566829750"
}

import {
  to = aws_s3_bucket_public_access_block.reports
  id = "spry-reports-818566829750"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "spry-reports-818566829750"
}

import {
  to = aws_s3_bucket_notification.reports
  id = "spry-reports-818566829750"
}

import {
  to = aws_vpc_endpoint.s3
  id = "vpce-0a8af5a3e1efa627a"
}

import {
  to = aws_security_group.builder
  id = "sg-0746151d4e34346cb"
}

import {
  to = aws_vpc_security_group_ingress_rule.database_from_builder
  id = "sgr-0a8d07c600d9897f3"
}

import {
  to = aws_sqs_queue.dead_letter
  id = "https://sqs.eu-north-1.amazonaws.com/818566829750/spry-report-requests-dlq"
}

import {
  to = aws_sqs_queue.requests
  id = "https://sqs.eu-north-1.amazonaws.com/818566829750/spry-report-requests"
}

import {
  to = aws_iam_role.scheduler
  id = "spry-report-scheduler"
}

import {
  to = aws_iam_role_policy.scheduler_send_to_queue
  id = "spry-report-scheduler:send-to-queue"
}

import {
  to = aws_scheduler_schedule.weekly
  id = "default/spry-weekly-report"
}

import {
  to = aws_iam_role.builder
  id = "spry-report-builder"
}

import {
  to = aws_iam_role_policy_attachment.builder_vpc
  id = "spry-report-builder/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

import {
  to = aws_iam_role_policy.builder_reports
  id = "spry-report-builder:reports"
}

import {
  to = aws_lambda_function.builder
  id = "spry-report-builder"
}

import {
  to = aws_lambda_event_source_mapping.requests
  id = "4ba7935e-d8cb-4775-b14a-53576b181bf2"
}

import {
  to = aws_iam_role.mailer
  id = "spry-report-mailer"
}

import {
  to = aws_iam_role_policy_attachment.mailer_logs
  id = "spry-report-mailer/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

import {
  to = aws_iam_role_policy.mailer_read_and_send
  id = "spry-report-mailer:read-and-send"
}

import {
  to = aws_lambda_function.mailer
  id = "spry-report-mailer"
}

import {
  to = aws_iam_role.parser
  id = "spry-agenda-parser"
}

import {
  to = aws_iam_role_policy_attachment.parser_logs
  id = "spry-agenda-parser/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

import {
  to = aws_iam_role_policy.parser_call_claude
  id = "spry-agenda-parser:call-claude"
}

import {
  to = aws_cloudwatch_log_group.parser
  id = "/aws/lambda/spry-agenda-parser"
}

import {
  to = aws_lambda_function.parser
  id = "spry-agenda-parser"
}

import {
  to = aws_lambda_function_url.parser
  id = "spry-agenda-parser"
}

