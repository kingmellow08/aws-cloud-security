# Shared mock values for `terraform test`. The AWS provider still validates
# ARN and JSON arguments on mocked resources, so computed attributes that
# feed those arguments need realistic shapes.

mock_data "aws_partition" {
  defaults = {
    partition = "aws"
  }
}

mock_data "aws_region" {
  defaults = {
    region = "us-east-1"
  }
}

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_iam_policy" {
  defaults = {
    arn = "arn:aws:iam::123456789012:policy/acs/terraform/acs-mock-workload-boundary"
  }
}

mock_data "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:us-east-1:123456789012:acs-baseline-security-alerts"
  }
}

mock_resource "aws_kms_key" {
  defaults = {
    arn = "arn:aws:kms:us-east-1:123456789012:key/4f1c2a6e-8d3b-4c5a-9e7f-0a1b2c3d4e5f"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::123456789012:role/acs/mock/acs-mock-role"
  }
}

mock_resource "aws_iam_policy" {
  defaults = {
    arn = "arn:aws:iam::123456789012:policy/acs/terraform/acs-mock-policy"
  }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = {
    arn = "arn:aws:logs:us-east-1:123456789012:log-group:/acs/mock/group"
  }
}

mock_resource "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:us-east-1:123456789012:acs-baseline-security-alerts"
  }
}

mock_resource "aws_s3_bucket" {
  defaults = {
    arn = "arn:aws:s3:::acs-mock-bucket"
  }
}

mock_resource "aws_cloudtrail" {
  defaults = {
    arn = "arn:aws:cloudtrail:us-east-1:123456789012:trail/acs-baseline-trail"
  }
}
