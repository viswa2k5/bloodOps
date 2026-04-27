terraform {
  backend "s3" {
    bucket = "bloodops-frontend-bucket"
    key    = "terraform/state/terraform.tfstate"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.50.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================
# VARIABLES
# ============================================================

variable "account_id" {
  default = "065837433541"
}

variable "region" {
  default = "us-east-1"
}

variable "frontend_bucket" {
  default = "bloodops-frontend-bucket"
}

variable "certificates_bucket" {
  default = "bloodops-certificates-bucket"
}

# ============================================================
# IAM ROLE FOR LAMBDA
# ============================================================

resource "aws_iam_role" "lambda_role" {
  name = "bloodops-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "bloodops-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.region}:${var.account_id}:table/Donors",
          "arn:aws:dynamodb:${var.region}:${var.account_id}:table/Requests",
          "arn:aws:dynamodb:${var.region}:${var.account_id}:table/Hospitals",
          "arn:aws:dynamodb:${var.region}:${var.account_id}:table/DonationHistory"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.certificates_bucket}",
          "arn:aws:s3:::${var.certificates_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          aws_sns_topic.urgent_alerts.arn,
          aws_sns_topic.reminder_alerts.arn,
          aws_sns_topic.admin_notifications.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

# ============================================================
# SNS TOPICS
# ============================================================

resource "aws_sns_topic" "urgent_alerts" {
  name = "urgent-blood-alerts"
  lifecycle { ignore_changes = all }
}

resource "aws_sns_topic" "reminder_alerts" {
  name = "reminder-alerts"
  lifecycle { ignore_changes = all }
}

resource "aws_sns_topic" "admin_notifications" {
  name = "admin-notifications"
  lifecycle { ignore_changes = all }
}

# ============================================================
# LAMBDA LAYERS
# ============================================================

resource "aws_lambda_layer_version" "reportlab_layer" {
  filename            = "reportlab_layer.zip"
  layer_name          = "reportlab-layer"
  compatible_runtimes = ["python3.11"]
  description         = "ReportLab library for PDF generation"
  lifecycle { ignore_changes = all }
}

# ============================================================
# LAMBDA FUNCTIONS
# ============================================================

data "archive_file" "donor_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/donor_function.py"
  output_path = "${path.module}/zips/donor_function.zip"
}

resource "aws_lambda_function" "donor_function" {
  filename         = data.archive_file.donor_zip.output_path
  function_name    = "bloodops-donor-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "donor_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.donor_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = { REGION = var.region }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "request_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/request_function.py"
  output_path = "${path.module}/zips/request_function.zip"
}

resource "aws_lambda_function" "request_function" {
  filename         = data.archive_file.request_zip.output_path
  function_name    = "bloodops-request-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "request_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.request_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = { REGION = var.region }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "match_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/match_function.py"
  output_path = "${path.module}/zips/match_function.zip"
}

resource "aws_lambda_function" "match_function" {
  filename         = data.archive_file.match_zip.output_path
  function_name    = "bloodops-match-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "match_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.match_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      REGION            = var.region
      URGENT_ALERTS_ARN = aws_sns_topic.urgent_alerts.arn
    }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "history_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/history_function.py"
  output_path = "${path.module}/zips/history_function.zip"
}

resource "aws_lambda_function" "history_function" {
  filename         = data.archive_file.history_zip.output_path
  function_name    = "bloodops-history-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "history_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.history_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = { REGION = var.region }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "certificate_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/certificate_function.py"
  output_path = "${path.module}/zips/certificate_function.zip"
}

resource "aws_lambda_function" "certificate_function" {
  filename         = data.archive_file.certificate_zip.output_path
  function_name    = "bloodops-certificate-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "certificate_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.certificate_zip.output_base64sha256
  timeout          = 60
  layers           = [aws_lambda_layer_version.reportlab_layer.arn]
  environment {
    variables = {
      REGION      = var.region
      BUCKET_NAME = var.certificates_bucket
    }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "reminder_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/reminder_function.py"
  output_path = "${path.module}/zips/reminder_function.zip"
}

resource "aws_lambda_function" "reminder_function" {
  filename         = data.archive_file.reminder_zip.output_path
  function_name    = "bloodops-reminder-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "reminder_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.reminder_zip.output_base64sha256
  timeout          = 60
  environment {
    variables = {
      REGION             = var.region
      REMINDER_TOPIC_ARN = aws_sns_topic.reminder_alerts.arn
    }
  }
  lifecycle { ignore_changes = [layers] }
}

data "archive_file" "admin_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/admin_function.py"
  output_path = "${path.module}/zips/admin_function.zip"
}

resource "aws_lambda_function" "admin_function" {
  filename         = data.archive_file.admin_zip.output_path
  function_name    = "bloodops-admin-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "admin_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.admin_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = { REGION = var.region }
  }
  lifecycle { ignore_changes = [layers] }
}

# ============================================================
# EVENTBRIDGE SCHEDULER
# ============================================================

resource "aws_iam_role" "eventbridge_role" {
  name = "bloodops-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  lifecycle { ignore_changes = all }
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "bloodops-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.reminder_function.arn
      }
    ]
  })
}

# ============================================================
# CLOUDWATCH ALARMS
# ============================================================

resource "aws_cloudwatch_metric_alarm" "donor_function_errors" {
  alarm_name          = "bloodops-donor-function-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Donor function error rate too high"
  dimensions          = { FunctionName = aws_lambda_function.donor_function.function_name }
  alarm_actions       = [aws_sns_topic.admin_notifications.arn]
  lifecycle { ignore_changes = all }
}

resource "aws_cloudwatch_metric_alarm" "request_function_errors" {
  alarm_name          = "bloodops-request-function-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Request function error rate too high"
  dimensions          = { FunctionName = aws_lambda_function.request_function.function_name }
  alarm_actions       = [aws_sns_topic.admin_notifications.arn]
  lifecycle { ignore_changes = all }
}

resource "aws_cloudwatch_metric_alarm" "match_function_errors" {
  alarm_name          = "bloodops-match-function-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Match function error rate too high"
  dimensions          = { FunctionName = aws_lambda_function.match_function.function_name }
  alarm_actions       = [aws_sns_topic.admin_notifications.arn]
  lifecycle { ignore_changes = all }
}

# ============================================================
# OUTPUTS
# ============================================================

output "urgent_alerts_topic_arn" {
  value = aws_sns_topic.urgent_alerts.arn
}

output "reminder_alerts_topic_arn" {
  value = aws_sns_topic.reminder_alerts.arn
}
