data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# BUG: main queue has no redrive_policy and there is no DLQ.
resource "aws_sqs_queue" "main" {
  name                       = "${var.course_prefix}-${var.student_id}-em08-order-errors"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 3600
  tags                       = { Student = var.student_id }
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
  name               = "${var.course_prefix}-${var.student_id}-em08-consumer-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sqs" {
  name = "consume-queue"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em08-consumer"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em08-consumer"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  tags             = { Student = var.student_id }
  depends_on       = [aws_cloudwatch_log_group.fn]
}

resource "aws_lambda_event_source_mapping" "esm" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.fn.arn
  batch_size       = 1
  enabled          = true
}
