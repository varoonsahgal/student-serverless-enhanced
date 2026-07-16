data "archive_file" "placeorder" {
  type        = "zip"
  source_file = "${path.module}/placeorder.py"
  output_path = "${path.module}/build/placeorder.zip"
}

data "archive_file" "notify" {
  type        = "zip"
  source_file = "${path.module}/notify.py"
  output_path = "${path.module}/build/notify.zip"
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

# ---- DynamoDB --------------------------------------------------------------
resource "aws_dynamodb_table" "orders" {
  name         = "${var.course_prefix}-${var.student_id}-em15-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"
  attribute {
    name = "orderId"
    type = "S"
  }
  tags = { Student = var.student_id }
}

# ---- SNS + inbox SQS -------------------------------------------------------
resource "aws_sns_topic" "orders" {
  name = "${var.course_prefix}-${var.student_id}-em15-orders"
  tags = { Student = var.student_id }
}

resource "aws_sqs_queue" "inbox" {
  name = "${var.course_prefix}-${var.student_id}-em15-inbox"
  tags = { Student = var.student_id }
}

resource "aws_sqs_queue_policy" "inbox" {
  queue_url = aws_sqs_queue.inbox.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.inbox.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "inbox" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.inbox.arn
  raw_message_delivery = true
}

# ---- notify Lambda ---------------------------------------------------------
resource "aws_iam_role" "notify" {
  name               = "${var.course_prefix}-${var.student_id}-em15-notify-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "notify_basic" {
  role       = aws_iam_role.notify.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "notify_publish" {
  name = "publish"
  role = aws_iam_role.notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.orders.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "notify" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em15-notify"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "notify" {
  function_name    = "${var.course_prefix}-${var.student_id}-em15-notify"
  role             = aws_iam_role.notify.arn
  handler          = "notify.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256
  timeout          = 10
  environment {
    # BUG D: points at a non-existent topic (real ARN + "-typo").
    variables = { TOPIC_ARN = "${aws_sns_topic.orders.arn}-typo" }
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.notify]
}

# ---- Step Functions --------------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em15-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy" "sfn_invoke" {
  name = "invoke-notify"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.notify.arn
    }]
  })
}

resource "aws_sfn_state_machine" "wf" {
  name     = "${var.course_prefix}-${var.student_id}-em15-wf"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"
  definition = jsonencode({
    Comment = "Acme order workflow"
    StartAt = "Notify"
    States = {
      Notify = {
        Type     = "Task"
        Resource = aws_lambda_function.notify.arn
        End      = true
      }
    }
  })
  tags = { Student = var.student_id }
}

# ---- placeorder Lambda -----------------------------------------------------
resource "aws_iam_role" "placeorder" {
  name               = "${var.course_prefix}-${var.student_id}-em15-placeorder-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "placeorder_basic" {
  role       = aws_iam_role.placeorder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# BUG B: only GetItem (no PutItem). BUG C: no states:StartExecution statement at all.
resource "aws_iam_role_policy" "placeorder_perms" {
  name = "placeorder-perms"
  role = aws_iam_role.placeorder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.orders.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "placeorder" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em15-placeorder"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "placeorder" {
  function_name    = "${var.course_prefix}-${var.student_id}-em15-placeorder"
  role             = aws_iam_role.placeorder.arn
  handler          = "placeorder.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.placeorder.output_path
  source_code_hash = data.archive_file.placeorder.output_base64sha256
  timeout          = 10
  environment {
    variables = {
      TABLE_NAME        = aws_dynamodb_table.orders.name
      STATE_MACHINE_ARN = aws_sfn_state_machine.wf.arn
    }
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.placeorder]
}

# ---- HTTP API --------------------------------------------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.course_prefix}-${var.student_id}-em15-api"
  protocol_type = "HTTP"
  tags          = { Student = var.student_id }
}

resource "aws_apigatewayv2_integration" "placeorder" {
  api_id           = aws_apigatewayv2_api.http.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.placeorder.invoke_arn
  # BUG A: handler expects 2.0 event shape -> KeyError -> 500.
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "checkout" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /checkout"
  target    = "integrations/${aws_apigatewayv2_integration.placeorder.id}"
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
  function_name = aws_lambda_function.placeorder.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
