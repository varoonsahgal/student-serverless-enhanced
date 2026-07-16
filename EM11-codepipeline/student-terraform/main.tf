data "aws_caller_identity" "me" {}

# ---- Deployable source artifact (buildspec + new app code) ------------------
data "archive_file" "source" {
  type        = "zip"
  output_path = "${path.module}/build/source.zip"
  source {
    filename = "buildspec.yml"
    content  = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Deploying $FUNCTION_NAME"
            - cd src && zip -r ../fn.zip . && cd ..
            - aws lambda update-function-code --function-name "$FUNCTION_NAME" --zip-file fileb://fn.zip
    EOT
  }
  source {
    filename = "src/app.py"
    content  = "def handler(event, context):\n    return {\"version\": \"v2-deployed-by-pipeline\"}\n"
  }
}

# ---- Initial target Lambda code --------------------------------------------
data "archive_file" "target_initial" {
  type        = "zip"
  output_path = "${path.module}/build/target_initial.zip"
  source {
    filename = "app.py"
    content  = "def handler(event, context):\n    return {\"version\": \"v1-initial\"}\n"
  }
}

# ---- Artifact/source bucket (versioning required by CodePipeline S3 source) -
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.course_prefix}-${var.student_id}-em11-${data.aws_caller_identity.me.account_id}"
  force_destroy = true
  tags          = { Student = var.student_id }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "source" {
  bucket      = aws_s3_bucket.artifacts.id
  key         = "source.zip"
  source      = data.archive_file.source.output_path
  source_hash = data.archive_file.source.output_base64sha256
  depends_on  = [aws_s3_bucket_versioning.artifacts]
}

# ---- Target Lambda (the thing being deployed) ------------------------------
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
  name               = "${var.course_prefix}-${var.student_id}-em11-fn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy_attachment" "fn_basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.course_prefix}-${var.student_id}-em11-target"
  retention_in_days = var.log_retention_days
  tags              = { Student = var.student_id }
}

resource "aws_lambda_function" "target" {
  function_name    = "${var.course_prefix}-${var.student_id}-em11-target"
  role             = aws_iam_role.fn.arn
  handler          = "app.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.target_initial.output_path
  source_code_hash = data.archive_file.target_initial.output_base64sha256
  timeout          = 10
  tags             = { Student = var.student_id }
  depends_on       = [aws_cloudwatch_log_group.fn]
}

# ---- CodeBuild -------------------------------------------------------------
data "aws_iam_policy_document" "assume_codebuild" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.course_prefix}-${var.student_id}-em11-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.assume_codebuild.json
  tags               = { Student = var.student_id }
}

# BUG: this policy has logs + S3 but NOT lambda:UpdateFunctionCode -> Deploy fails.
resource "aws_iam_role_policy" "codebuild" {
  name = "codebuild-perms"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_codebuild_project" "deploy" {
  name         = "${var.course_prefix}-${var.student_id}-em11-deploy"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"
    environment_variable {
      name  = "FUNCTION_NAME"
      value = aws_lambda_function.target.function_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Deploying $FUNCTION_NAME"
            - cd src && zip -r ../fn.zip . && cd ..
            - aws lambda update-function-code --function-name "$FUNCTION_NAME" --zip-file fileb://fn.zip
    EOT
  }
  tags = { Student = var.student_id }
}

# ---- CodePipeline ----------------------------------------------------------
data "aws_iam_policy_document" "assume_pipeline" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${var.course_prefix}-${var.student_id}-em11-pipeline-role"
  assume_role_policy = data.aws_iam_policy_document.assume_pipeline.json
  tags               = { Student = var.student_id }
}

resource "aws_iam_role_policy" "pipeline" {
  name = "pipeline-perms"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning"]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.deploy.arn
      },
    ]
  })
}

resource "aws_codepipeline" "pipe" {
  name     = "${var.course_prefix}-${var.student_id}-em11-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["src"]
      configuration = {
        S3Bucket             = aws_s3_bucket.artifacts.bucket
        S3ObjectKey          = "source.zip"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["src"]
      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }

  depends_on = [aws_s3_object.source]
  tags       = { Student = var.student_id }
}
