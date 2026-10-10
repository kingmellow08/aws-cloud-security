locals {
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}"
}

data "aws_partition" "current" {}

# See modules/kms-key/main.tf for why the protected/unprotected pair exists.
resource "aws_s3_bucket" "protected" {
  count = var.prevent_destroy ? 1 : 0

  bucket        = var.bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = var.bucket_name })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "unprotected" {
  count = var.prevent_destroy ? 0 : 1

  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = var.bucket_name })
}

locals {
  # Select attributes individually; referencing the whole aws_s3_bucket
  # object drags in its deprecated inline-configuration attributes.
  bucket_id   = one(concat(aws_s3_bucket.protected[*].id, aws_s3_bucket.unprotected[*].id))
  bucket_name = one(concat(aws_s3_bucket.protected[*].bucket, aws_s3_bucket.unprotected[*].bucket))
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = local.bucket_id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = local.bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = local.bucket_id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = local.bucket_id

  rule {
    id     = "retain-history"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]
      content {
        days = expiration.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "this" {
  source_policy_documents = var.additional_policy_json == null ? [] : [var.additional_policy_json]

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyOutdatedTls"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  statement {
    sid       = "DenyNonKmsEncryptionHeaders"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms", "aws:kms:dsse"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = local.bucket_id
  policy = data.aws_iam_policy_document.this.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
