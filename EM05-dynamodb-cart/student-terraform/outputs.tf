output "api_endpoints" {
  description = "Base invoke URL per student (append /cart?user=<name>)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "table_names" {
  value = aws_dynamodb_table.cart.name
}
