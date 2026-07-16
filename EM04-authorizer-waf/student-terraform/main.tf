data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# ---- Cognito ---------------------------------------------------------------
resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.course_prefix}-${var.student_id}-em04-pool"
  auto_verified_attributes = ["email"]
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  tags = { Student = var.student_id }
}

resource "aws_cognito_user_pool_client" "client" {
  name            = "${var.course_prefix}-${var.student_id}-em04-client"
  user_pool_id    = aws_cognito_user_pool.pool.id
  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

resource "aws_cognito_user" "shopper" {
  user_pool_id = aws_cognito_user_pool.pool.id
  username     = "shopper@acme.example"
  password     = var.seed_password
  attributes = {
    email          = "shopper@acme.example"
    email_verified = "true"
  }
}

# ---- Backend Lambda --------------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em04-fn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em04-orders"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em04-orders"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  tags             = { Student = var.student_id }
  depends_on       = [aws_cloudwatch_log_group.fn]
}

# ---- REST API + authorizer -------------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.course_prefix}-${var.student_id}-em04-api"
  tags = { Student = var.student_id }
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.pool.arn]
  # BUG 1: clients send "Authorization"; this reads a header named "Auth" -> 401.
  identity_source = "method.request.header.Auth"
}

resource "aws_api_gateway_method" "get_orders" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_orders" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.get_orders.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.fn.invoke_arn
}

resource "aws_api_gateway_deployment" "dep" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.get_orders.id,
      aws_api_gateway_integration.get_orders.id,
      aws_api_gateway_authorizer.cognito.identity_source,
    ]))
  }
  depends_on = [aws_api_gateway_integration.get_orders]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.dep.id
  stage_name    = "prod"
  tags          = { Student = var.student_id }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromRestApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ---- WAF -------------------------------------------------------------------
resource "aws_wafv2_web_acl" "acl" {
  name  = "${var.course_prefix}-${var.student_id}-em04-acl"
  scope = "REGIONAL"

  # BUG 2: block-by-default with no allow rule denies every request (403).
  default_action {
    block {}
  }

  rule {
    name     = "ip-reputation"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ipReputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "anonymous-ip"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "anonymousIp"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.course_prefix}-${var.student_id}-em04-acl"
    sampled_requests_enabled   = true
  }
  tags = { Student = var.student_id }
}

resource "aws_wafv2_web_acl_association" "assoc" {
  resource_arn = aws_api_gateway_stage.prod.arn
  web_acl_arn  = aws_wafv2_web_acl.acl.arn
}
