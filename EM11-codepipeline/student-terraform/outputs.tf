output "pipeline_names" {
  value = aws_codepipeline.pipe.name
}

output "target_function_names" {
  value = aws_lambda_function.target.function_name
}

output "codebuild_role_names" {
  value = aws_iam_role.codebuild.name
}
