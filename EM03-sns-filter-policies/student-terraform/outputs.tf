output "topic_arns" {
  value = aws_sns_topic.orders.arn
}

output "priority_queue_urls" {
  value = aws_sqs_queue.priority.url
}

output "standard_queue_urls" {
  value = aws_sqs_queue.standard.url
}
