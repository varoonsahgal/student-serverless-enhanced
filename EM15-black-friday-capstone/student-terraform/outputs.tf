output "api_endpoints" {
  description = "Base invoke URL per student (append /checkout)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "table_names" {
  value = aws_dynamodb_table.orders.name
}

output "state_machine_arns" {
  value = aws_sfn_state_machine.wf.arn
}

output "inbox_queue_urls" {
  value = aws_sqs_queue.inbox.url
}
