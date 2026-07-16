output "api_urls" {
  description = "REST API prod invoke URL per student (append /orders)."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "user_pool_ids" {
  value = aws_cognito_user_pool.pool.id
}

output "client_ids" {
  value = aws_cognito_user_pool_client.client.id
}
