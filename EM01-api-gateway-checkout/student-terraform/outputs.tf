output "api_endpoints" {
  description = "Base invoke URL per student (append /products, /cart, /place-order)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "function_names" {
  description = "Storefront Lambda name per student."
  value       = aws_lambda_function.fn.function_name
}
