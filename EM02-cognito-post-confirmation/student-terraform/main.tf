data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

resource "aws_sns_topic" "notify" {
  name = "${var.course_prefix}-${var.student_id}-em02-notify"
  tags = { Student = var.student_id }
}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fn" {
  name               = "${var.course_prefix}-${var.student_id}-em02-fn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The Lambda CAN subscribe to SNS -- that permission is correct. It is simply never called.
resource "aws_iam_role_policy" "sns" {
  name = "sns-subscribe"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Subscribe"]
      Resource = aws_sns_topic.notify.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em02-subscribe"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em02-subscribe"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  environment {
    variables = { SNS_TOPIC_ARN = aws_sns_topic.notify.arn }
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.fn]
}

resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.course_prefix}-${var.student_id}-em02-pool"
  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  # BUG: no lambda_config block -> the PostConfirmation trigger is never wired.
  tags = { Student = var.student_id }
}

resource "aws_cognito_user_pool_client" "client" {
  name            = "${var.course_prefix}-${var.student_id}-em02-client"
  user_pool_id    = aws_cognito_user_pool.pool.id
  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

# BUG: no aws_lambda_permission for cognito-idp.amazonaws.com.
