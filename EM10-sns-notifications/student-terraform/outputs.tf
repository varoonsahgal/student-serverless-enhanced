output "function_names" {
  value = aws_lambda_function.fn.function_name
}

output "topic_arns" {
  value = aws_sns_topic.orders.arn
}

output "inbox_queue_urls" {
  value = aws_sqs_queue.inbox.url
}
