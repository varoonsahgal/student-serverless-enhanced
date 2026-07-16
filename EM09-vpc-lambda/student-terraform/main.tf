data "aws_availability_zones" "azs" {
  state = "available"
}

data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# ---- Per-student VPC -------------------------------------------------------
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.course_prefix}-${var.student_id}-em09-vpc", Student = var.student_id }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.azs.names[0]
  tags              = { Name = "${var.course_prefix}-${var.student_id}-em09-private", Student = var.student_id }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.course_prefix}-${var.student_id}-em09-rt", Student = var.student_id }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "lambda" {
  name        = "${var.course_prefix}-${var.student_id}-em09-lambda-sg"
  description = "Lambda egress"
  vpc_id      = aws_vpc.vpc.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Student = var.student_id }
}

# BUG: no aws_vpc_endpoint for DynamoDB -> the private subnet has no route to the service.

# ---- DynamoDB --------------------------------------------------------------
resource "aws_dynamodb_table" "t" {
  name         = "${var.course_prefix}-${var.student_id}-em09-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  attribute {
    name = "pk"
    type = "S"
  }
  tags = { Student = var.student_id }
}

# ---- Lambda (in VPC) -------------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em09-fn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

# VPC access managed policy also grants CloudWatch Logs permissions.
resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ddb" {
  name = "ddb-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.t.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em09-data"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em09-data"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 15
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.t.name }
  }
  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy_attachment.vpc]
}
