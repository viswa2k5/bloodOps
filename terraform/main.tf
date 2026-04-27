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
      version = "= 2.6.0"
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
        Action = [
          "sns:Publish"
        ]
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
      }
    ]
  })
}

# ============================================================
# SNS TOPICS
# ============================================================

resource "aws_sns_topic" "urgent_alerts" {
  name = "urgent-blood-alerts"
}

resource "aws_sns_topic" "reminder_alerts" {
  name = "reminder-alerts"
}

resource "aws_sns_topic" "admin_notifications" {
  name = "admin-notifications"
}

# ============================================================
# LAMBDA LAYERS (reportlab for certificate function)
# ============================================================

resource "aws_lambda_layer_version" "reportlab_layer" {
  filename            = "reportlab_layer.zip"
  layer_name          = "reportlab-layer"
  compatible_runtimes = ["python3.11"]
  description         = "ReportLab library for PDF generation"
}

# ============================================================
# LAMBDA FUNCTIONS
# ============================================================

# --- donor_function ---
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
    variables = {
      REGION = var.region
    }
  }
}

resource "aws_cloudwatch_log_group" "donor_logs" {
  name              = "/aws/lambda/bloodops-donor-function"
  retention_in_days = 7
}

# --- request_function ---
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
    variables = {
      REGION = var.region
    }
  }
}

resource "aws_cloudwatch_log_group" "request_logs" {
  name              = "/aws/lambda/bloodops-request-function"
  retention_in_days = 7
}

# --- match_function ---
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
      REGION             = var.region
      URGENT_ALERTS_ARN  = aws_sns_topic.urgent_alerts.arn
    }
  }
}

resource "aws_cloudwatch_log_group" "match_logs" {
  name              = "/aws/lambda/bloodops-match-function"
  retention_in_days = 7
}

# --- history_function ---
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
    variables = {
      REGION = var.region
    }
  }
}

resource "aws_cloudwatch_log_group" "history_logs" {
  name              = "/aws/lambda/bloodops-history-function"
  retention_in_days = 7
}

# --- certificate_function ---
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
}

resource "aws_cloudwatch_log_group" "certificate_logs" {
  name              = "/aws/lambda/bloodops-certificate-function"
  retention_in_days = 7
}

# --- reminder_function ---
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
}

resource "aws_cloudwatch_log_group" "reminder_logs" {
  name              = "/aws/lambda/bloodops-reminder-function"
  retention_in_days = 7
}

# --- admin_function ---
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
    variables = {
      REGION = var.region
    }
  }
}

resource "aws_cloudwatch_log_group" "admin_logs" {
  name              = "/aws/lambda/bloodops-admin-function"
  retention_in_days = 7
}

# ============================================================
# API GATEWAY
# ============================================================

resource "aws_api_gateway_rest_api" "bloodops_api" {
  name        = "bloodops-api"
  description = "BloodOps API Gateway"
}

# --- /donors resource ---
resource "aws_api_gateway_resource" "donors" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "donors"
}

resource "aws_api_gateway_method" "donors_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.donors.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "donors_post" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.donors.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "donors_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.donors.id
  http_method             = aws_api_gateway_method.donors_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.donor_function.invoke_arn
}

resource "aws_api_gateway_integration" "donors_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.donors.id
  http_method             = aws_api_gateway_method.donors_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.donor_function.invoke_arn
}

# CORS for /donors
resource "aws_api_gateway_method" "donors_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.donors.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "donors_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.donors.id
  http_method = aws_api_gateway_method.donors_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "donors_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.donors.id
  http_method = aws_api_gateway_method.donors_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "donors_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.donors.id
  http_method = aws_api_gateway_method.donors_options.http_method
  status_code = aws_api_gateway_method_response.donors_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /requests resource ---
resource "aws_api_gateway_resource" "requests" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "requests"
}

resource "aws_api_gateway_method" "requests_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "requests_post" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "requests_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.requests.id
  http_method             = aws_api_gateway_method.requests_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.request_function.invoke_arn
}

resource "aws_api_gateway_integration" "requests_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.requests.id
  http_method             = aws_api_gateway_method.requests_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.request_function.invoke_arn
}

# CORS for /requests
resource "aws_api_gateway_method" "requests_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.requests.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "requests_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "requests_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "requests_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.requests.id
  http_method = aws_api_gateway_method.requests_options.http_method
  status_code = aws_api_gateway_method_response.requests_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /match resource ---
resource "aws_api_gateway_resource" "match" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "match"
}

resource "aws_api_gateway_method" "match_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.match.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "match_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.match.id
  http_method             = aws_api_gateway_method.match_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.match_function.invoke_arn
}

# CORS for /match
resource "aws_api_gateway_method" "match_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.match.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "match_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.match_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "match_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.match_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "match_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.match_options.http_method
  status_code = aws_api_gateway_method_response.match_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /history resource ---
resource "aws_api_gateway_resource" "history" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "history"
}

resource "aws_api_gateway_method" "history_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.history.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "history_post" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.history.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "history_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.history.id
  http_method             = aws_api_gateway_method.history_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.history_function.invoke_arn
}

resource "aws_api_gateway_integration" "history_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.history.id
  http_method             = aws_api_gateway_method.history_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.history_function.invoke_arn
}

# CORS for /history
resource "aws_api_gateway_method" "history_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.history.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "history_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.history.id
  http_method = aws_api_gateway_method.history_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "history_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.history.id
  http_method = aws_api_gateway_method.history_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "history_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.history.id
  http_method = aws_api_gateway_method.history_options.http_method
  status_code = aws_api_gateway_method_response.history_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /certificate resource ---
resource "aws_api_gateway_resource" "certificate" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "certificate"
}

resource "aws_api_gateway_method" "certificate_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.certificate.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "certificate_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.certificate.id
  http_method             = aws_api_gateway_method.certificate_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.certificate_function.invoke_arn
}

# CORS for /certificate
resource "aws_api_gateway_method" "certificate_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.certificate.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "certificate_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.certificate.id
  http_method = aws_api_gateway_method.certificate_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "certificate_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.certificate.id
  http_method = aws_api_gateway_method.certificate_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "certificate_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.certificate.id
  http_method = aws_api_gateway_method.certificate_options.http_method
  status_code = aws_api_gateway_method_response.certificate_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /admin resource ---
resource "aws_api_gateway_resource" "admin" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  parent_id   = aws_api_gateway_rest_api.bloodops_api.root_resource_id
  path_part   = "admin"
}

resource "aws_api_gateway_method" "admin_get" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.admin.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "admin_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.bloodops_api.id
  resource_id             = aws_api_gateway_resource.admin.id
  http_method             = aws_api_gateway_method.admin_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.admin_function.invoke_arn
}

# CORS for /admin
resource "aws_api_gateway_method" "admin_options" {
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  resource_id   = aws_api_gateway_resource.admin.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "admin_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.admin.id
  http_method = aws_api_gateway_method.admin_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "admin_options_200" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.admin.id
  http_method = aws_api_gateway_method.admin_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "admin_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id
  resource_id = aws_api_gateway_resource.admin.id
  http_method = aws_api_gateway_method.admin_options.http_method
  status_code = aws_api_gateway_method_response.admin_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ============================================================
# API GATEWAY DEPLOYMENT
# ============================================================

resource "aws_api_gateway_deployment" "bloodops_deployment" {
  rest_api_id = aws_api_gateway_rest_api.bloodops_api.id

  depends_on = [
    aws_api_gateway_integration.donors_get_integration,
    aws_api_gateway_integration.donors_post_integration,
    aws_api_gateway_integration.requests_get_integration,
    aws_api_gateway_integration.requests_post_integration,
    aws_api_gateway_integration.match_get_integration,
    aws_api_gateway_integration.history_get_integration,
    aws_api_gateway_integration.history_post_integration,
    aws_api_gateway_integration.certificate_get_integration,
    aws_api_gateway_integration.admin_get_integration,
  ]
}

resource "aws_api_gateway_stage" "bloodops_stage" {
  deployment_id = aws_api_gateway_deployment.bloodops_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.bloodops_api.id
  stage_name    = "prod"
  lifecycle {
    ignore_changes = all
  }
}

# ============================================================
# LAMBDA PERMISSIONS FOR API GATEWAY
# ============================================================

resource "aws_lambda_permission" "donor_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.donor_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "request_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.request_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "match_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.match_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "history_api_permission" {
  statement_id  = "AllowAPIGatewayInvokeHistory"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.history_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "certificate_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.certificate_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "admin_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bloodops_api.execution_arn}/*/*"
}

# ============================================================
# EVENTBRIDGE SCHEDULER — Daily Reminder at 9AM IST
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

resource "aws_scheduler_schedule" "daily_reminder" {
  name = "bloodops-daily-reminder"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(30 3 * * ? *)"

  target {
    arn      = aws_lambda_function.reminder_function.arn
    role_arn = aws_iam_role.eventbridge_role.arn
  }
  lifecycle {
    ignore_changes = all
  }
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

  dimensions = {
    FunctionName = aws_lambda_function.donor_function.function_name
  }

  alarm_actions = [aws_sns_topic.admin_notifications.arn]
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

  dimensions = {
    FunctionName = aws_lambda_function.request_function.function_name
  }

  alarm_actions = [aws_sns_topic.admin_notifications.arn]
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

  dimensions = {
    FunctionName = aws_lambda_function.match_function.function_name
  }

  alarm_actions = [aws_sns_topic.admin_notifications.arn]
}

# ============================================================
# OUTPUTS
# ============================================================

output "api_gateway_url" {
  value       = "https://${aws_api_gateway_rest_api.bloodops_api.id}.execute-api.${var.region}.amazonaws.com/prod"
  description = "Base URL for BloodOps API - paste this into your frontend and admin HTML files"
}

output "urgent_alerts_topic_arn" {
  value = aws_sns_topic.urgent_alerts.arn
}

output "reminder_alerts_topic_arn" {
  value = aws_sns_topic.reminder_alerts.arn
}
