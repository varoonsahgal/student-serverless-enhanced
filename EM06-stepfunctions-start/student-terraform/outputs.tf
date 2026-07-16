output "api_endpoints" {
  description = "Base invoke URL per student (append /place-order)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "state_machine_arns" {
  value = aws_sfn_state_machine.fulfillment.arn
}
