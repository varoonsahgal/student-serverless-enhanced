output "state_machine_arns" {
  value = aws_sfn_state_machine.fulfillment.arn
}

output "payment_function_names" {
  value = aws_lambda_function.payment.function_name
}
