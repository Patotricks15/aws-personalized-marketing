# ─── S3: historical interaction data + customer profiles feeding the recommendation engine

resource "aws_s3_bucket" "customer_data" {
  bucket = "${local.name_prefix}-${var.customer_data_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.customer_data_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "customer_data" {
  bucket = aws_s3_bucket.customer_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "customers" {
  bucket       = aws_s3_bucket.customer_data.id
  key          = "customers.json"
  source       = "${path.module}/src/data/customers.json"
  etag         = filemd5("${path.module}/src/data/customers.json")
  content_type = "application/json"
}

resource "aws_s3_object" "historical_interactions" {
  bucket       = aws_s3_bucket.customer_data.id
  key          = "historical_interactions.json"
  source       = "${path.module}/src/data/historical_interactions.json"
  etag         = filemd5("${path.module}/src/data/historical_interactions.json")
  content_type = "application/json"
}

# ─── SES: verified sender identity used to deliver marketing emails ──────────

resource "aws_ses_email_identity" "sender" {
  email = var.ses_sender_email
}

# ─── Lambda: send_emails — delivers a single personalized email via SES ─────

resource "aws_iam_role" "send_emails" {
  name = "${local.name_prefix}-send-emails"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "send_emails_basic" {
  role       = aws_iam_role.send_emails.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "send_emails_ses" {
  name = "${local.name_prefix}-send-emails-ses"
  role = aws_iam_role.send_emails.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

resource "null_resource" "send_emails_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/send_emails/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} send_emails"
  }
}

data "archive_file" "send_emails_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/send_emails/handler.py"
  output_path = "${path.module}/.build/send_emails.zip"

  depends_on = [null_resource.send_emails_package]
}

resource "aws_lambda_function" "send_emails" {
  function_name = "${local.name_prefix}-send-emails"
  role          = aws_iam_role.send_emails.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 128

  filename         = data.archive_file.send_emails_zip.output_path
  source_code_hash = data.archive_file.send_emails_zip.output_base64sha256

  environment {
    variables = {
      REGION       = var.aws_region
      SENDER_EMAIL = var.ses_sender_email
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-send-emails"
  })

  depends_on = [
    aws_iam_role_policy_attachment.send_emails_basic,
    aws_iam_role_policy.send_emails_ses,
  ]
}

# ─── Lambda: recommendation_engine — builds prompts and generates the email content

resource "aws_iam_role" "recommendation_engine" {
  name = "${local.name_prefix}-recommendation-engine"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "recommendation_engine_basic" {
  role       = aws_iam_role.recommendation_engine.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "recommendation_engine_s3" {
  name = "${local.name_prefix}-recommendation-engine-s3"
  role = aws_iam_role.recommendation_engine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.customer_data.arn, "${aws_s3_bucket.customer_data.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "recommendation_engine_bedrock" {
  name = "${local.name_prefix}-recommendation-engine-bedrock"
  role = aws_iam_role.recommendation_engine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
    }]
  })
}

resource "aws_iam_role_policy" "recommendation_engine_invoke" {
  name = "${local.name_prefix}-recommendation-engine-invoke"
  role = aws_iam_role.recommendation_engine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.send_emails.arn
    }]
  })
}

resource "null_resource" "recommendation_engine_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/recommendation_engine/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} recommendation_engine"
  }
}

data "archive_file" "recommendation_engine_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/recommendation_engine/handler.py"
  output_path = "${path.module}/.build/recommendation_engine.zip"

  depends_on = [null_resource.recommendation_engine_package]
}

resource "aws_lambda_function" "recommendation_engine" {
  function_name = "${local.name_prefix}-recommendation-engine"
  role          = aws_iam_role.recommendation_engine.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.recommendation_engine_zip.output_path
  source_code_hash = data.archive_file.recommendation_engine_zip.output_base64sha256

  environment {
    variables = {
      REGION                    = var.aws_region
      DATA_BUCKET               = aws_s3_bucket.customer_data.bucket
      GENERATION_MODEL_ARN      = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
      SEND_EMAILS_FUNCTION_NAME = aws_lambda_function.send_emails.function_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-recommendation-engine"
  })

  depends_on = [
    aws_iam_role_policy_attachment.recommendation_engine_basic,
    aws_iam_role_policy.recommendation_engine_s3,
    aws_iam_role_policy.recommendation_engine_bedrock,
    aws_iam_role_policy.recommendation_engine_invoke,
    aws_s3_object.customers,
    aws_s3_object.historical_interactions,
  ]
}

# ─── EventBridge: schedules the personalized marketing campaign run ─────────

resource "aws_cloudwatch_event_rule" "campaign_schedule" {
  name                = "${local.name_prefix}-campaign-schedule"
  schedule_expression = var.schedule_expression
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "campaign_schedule" {
  rule = aws_cloudwatch_event_rule.campaign_schedule.name
  arn  = aws_lambda_function.recommendation_engine.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recommendation_engine.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.campaign_schedule.arn
}
