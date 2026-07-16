output "function_names" {
  value = aws_lambda_function.fn.function_name
}

output "vpc_ids" {
  value = aws_vpc.vpc.id
}

output "route_table_ids" {
  value = aws_route_table.private.id
}
