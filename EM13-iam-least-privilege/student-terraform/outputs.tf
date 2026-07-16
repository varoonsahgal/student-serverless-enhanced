output "function_names" {
  value = aws_lambda_function.fn.function_name
}

output "table_names" {
  value = aws_dynamodb_table.orders.name
}
