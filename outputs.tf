output "recommendation_engine_function_name" {
  description = "Name of the Lambda that builds prompts and generates personalized email content."
  value       = aws_lambda_function.recommendation_engine.function_name
}

output "send_emails_function_name" {
  description = "Name of the Lambda that delivers marketing emails through SES."
  value       = aws_lambda_function.send_emails.function_name
}

output "customer_data_bucket" {
  description = "Name of the S3 bucket holding historical interaction data and customer profiles."
  value       = aws_s3_bucket.customer_data.bucket
}

output "campaign_schedule_rule" {
  description = "Name of the EventBridge rule that triggers the recommendation engine."
  value       = aws_cloudwatch_event_rule.campaign_schedule.name
}
