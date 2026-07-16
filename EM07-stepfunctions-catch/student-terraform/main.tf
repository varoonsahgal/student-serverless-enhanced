data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# ---- payment Lambda --------------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em07-payment-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em07-payment"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "payment" {
  function_name    = "${var.course_prefix}-${var.student_id}-em07-payment"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  tags             = { Student = var.student_id }
  depends_on       = [aws_cloudwatch_log_group.fn]
}

# ---- state machine ---------------------------------------------------------
data "aws_iam_policy_document" "assume_sfn" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.course_prefix}-${var.student_id}-em07-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy" "sfn_invoke" {
  name = "invoke-payment"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.payment.arn
    }]
  })
}

resource "aws_sfn_state_machine" "fulfillment" {
  name     = "${var.course_prefix}-${var.student_id}-em07-fulfillment"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"
  # BUG: ProcessPayment has no Retry and no Catch -> a failing payment fails the whole execution.
  definition = jsonencode({
    Comment = "Acme order fulfillment (no error handling)"
    StartAt = "ProcessPayment"
    States = {
      ProcessPayment = {
        Type     = "Task"
        Resource = aws_lambda_function.payment.arn
        End      = true
      }
    }
  })
  tags = { Student = var.student_id }
}
