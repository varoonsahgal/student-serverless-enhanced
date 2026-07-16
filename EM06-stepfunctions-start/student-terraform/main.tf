data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# ---- State machine (trivial, always succeeds) ------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em06-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = { Student = var.student_id }
}

resource "aws_sfn_state_machine" "fulfillment" {
  name     = "${var.course_prefix}-${var.student_id}-em06-fulfillment"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"
  definition = jsonencode({
    Comment = "Acme order fulfillment (demo)"
    StartAt = "RecordOrder"
    States = {
      RecordOrder = {
        Type   = "Pass"
        Result = { status = "PROCESSED" }
        End    = true
      }
    }
  })
  tags = { Student = var.student_id }
}

# ---- placeorder Lambda -----------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em06-placeorder-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# BUG: no states:StartExecution policy -> start_execution() -> AccessDeniedException.

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em06-placeorder"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em06-placeorder"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  environment {
    variables = { STATE_MACHINE_ARN = aws_sfn_state_machine.fulfillment.arn }
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.fn]
}

# ---- HTTP API --------------------------------------------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.course_prefix}-${var.student_id}-em06-api"
  protocol_type = "HTTP"
  tags          = { Student = var.student_id }
}

resource "aws_apigatewayv2_integration" "fn" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.fn.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_order" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /place-order"
  target    = "integrations/${aws_apigatewayv2_integration.fn.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = { Student = var.student_id }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
