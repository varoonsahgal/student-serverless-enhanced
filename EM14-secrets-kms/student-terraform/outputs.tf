output "function_names" {
  value = aws_lambda_function.fn.function_name
}

output "key_arns" {
  value = aws_kms_key.secret.arn
}

output "secret_arns" {
  value = aws_secretsmanager_secret.db.arn
}
