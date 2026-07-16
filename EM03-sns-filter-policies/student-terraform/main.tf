resource "aws_sns_topic" "orders" {
  name = "${var.course_prefix}-${var.student_id}-em03-orders"
  tags = { Student = var.student_id }
}

resource "aws_sqs_queue" "priority" {
  name = "${var.course_prefix}-${var.student_id}-em03-priority"
  tags = { Student = var.student_id }
}

resource "aws_sqs_queue" "standard" {
  name = "${var.course_prefix}-${var.student_id}-em03-standard"
  tags = { Student = var.student_id }
}

resource "aws_sqs_queue_policy" "priority" {
  queue_url = aws_sqs_queue.priority.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.priority.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}

resource "aws_sqs_queue_policy" "standard" {
  queue_url = aws_sqs_queue.standard.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.standard.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "priority" {
  topic_arn           = aws_sns_topic.orders.arn
  protocol            = "sqs"
  endpoint            = aws_sqs_queue.priority.arn
  filter_policy_scope = "MessageAttributes"
  # BUG: key is "orderType" but publishers send "order_type" -> priority events are filtered out.
  filter_policy = jsonencode({ orderType = ["priority"] })
}

resource "aws_sns_topic_subscription" "standard" {
  topic_arn           = aws_sns_topic.orders.arn
  protocol            = "sqs"
  endpoint            = aws_sqs_queue.standard.arn
  filter_policy_scope = "MessageAttributes"
  filter_policy       = jsonencode({ order_type = ["standard"] })
}
