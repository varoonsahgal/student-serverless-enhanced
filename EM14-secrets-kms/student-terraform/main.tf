data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/build/fn.zip"
}

# ---- Customer-managed KMS key + secret -------------------------------------
resource "aws_kms_key" "secret" {
  description             = "${var.course_prefix}-${var.student_id}-em14 secret encryption"
  deletion_window_in_days = 7
  tags                    = { Student = var.student_id }
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.course_prefix}-${var.student_id}-em14-db-creds"
  kms_key_id              = aws_kms_key.secret.arn
  recovery_window_in_days = 0
  tags                    = { Student = var.student_id }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = "acme_app", password = "s3cr3t-lab-only" })
}

# ---- Lambda ----------------------------------------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em14-fn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# BUG: allows GetSecretValue but NOT kms:Decrypt -> reading the customer-key-encrypted secret is denied.
resource "aws_iam_role_policy" "secret" {
  name = "read-secret"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em14-checkout"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "fn" {
  function_name    = "${var.course_prefix}-${var.student_id}-em14-checkout"
  role             = aws_iam_role.fn.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  timeout          = 10
  environment {
    variables = { SECRET_ARN = aws_secretsmanager_secret.db.arn }
  }
  tags       = { Student = var.student_id }
  depends_on = [aws_cloudwatch_log_group.fn]
}
