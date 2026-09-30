variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-personalized-marketing"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "customer_data_bucket_name" {
  description = "Name of the S3 bucket holding historical interaction data and customer profiles."
  type        = string
  default     = "customer-data"
}

variable "generation_model_id" {
  description = "Bedrock foundation model id used to generate personalized marketing emails."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "ses_sender_email" {
  description = "Verified SES sender address used to deliver marketing emails."
  type        = string
  default     = "marketing@floci-shop.example.com"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression that triggers the recommendation engine campaign run."
  type        = string
  default     = "rate(1 day)"
}
