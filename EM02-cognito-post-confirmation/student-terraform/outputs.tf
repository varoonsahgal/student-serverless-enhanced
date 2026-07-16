output "user_pool_ids" {
  value = aws_cognito_user_pool.pool.id
}

output "client_ids" {
  value = aws_cognito_user_pool_client.client.id
}

output "topic_arns" {
  value = aws_sns_topic.notify.arn
}

output "function_names" {
  value = aws_lambda_function.fn.function_name
}
