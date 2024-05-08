terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.83.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile name"
  default     = "total-dev"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "shutdown-and-start-ec2-total"
  acl    = "private"

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  key    = "lambda.zip"
  source = "lambda.zip"  

  depends_on = [aws_s3_bucket.lambda_bucket]
}


resource "aws_iam_role" "lambda_role" {
  name = "ec2_scheduler_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "ec2_scheduler_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "ec2_scheduler" {
  function_name = "EC2Scheduler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda.lambda_handler"
  runtime       = "python3.8"
  s3_bucket     = aws_s3_bucket.lambda_bucket.bucket
  s3_key        = "lambda.zip"
}

# Evento para iniciar instancias a las 9 AM GTM-3 (12 PM UTC)
resource "aws_cloudwatch_event_rule" "start_ec2" {
  name                = "start-ec2-in-the-morning"
  schedule_expression = "cron(0 12 * * ? *)"
}

resource "aws_cloudwatch_event_target" "start_ec2_target" {
  rule      = aws_cloudwatch_event_rule.start_ec2.name
  target_id = "StartEC2Instances"
  arn       = aws_lambda_function.ec2_scheduler.arn
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "allow_ec2_to_call_lambda" {
  statement_id  = "AllowExecutionFromEC2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "ec2.amazonaws.com"
  source_arn    = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${aws_cloudwatch_event_rule.start_ec2.name}"
}



# Evento para detener instancias a las 18 PM GTM-3 (21 PM UTC)
resource "aws_cloudwatch_event_rule" "stop_ec2" {
  name                = "stop-ec2-at-night"
  schedule_expression = "cron(0 19 * * ? *)"
}

resource "aws_cloudwatch_event_target" "stop_ec2_target" {
  rule      = aws_cloudwatch_event_rule.stop_ec2.name
  target_id = "StopEC2Instances"
  arn       = aws_lambda_function.ec2_scheduler.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_stop_ec2" {
  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_ec2.arn
}
