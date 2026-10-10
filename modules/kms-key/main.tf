data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "this" {
  # Caller-supplied statements (service principals, encryption-context
  # conditions) are merged with the baseline account-admin statement below.
  source_policy_documents = var.additional_policy_json == null ? [] : [var.additional_policy_json]

  statement {
    sid       = "EnableAccountIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

# `lifecycle` arguments cannot be set from variables, so the key is declared
# twice and exactly one instance exists. Switching between the two is a
# deliberate operation documented in docs/terraform-state-ownership.md
# ("Decommissioning a protected resource").
resource "aws_kms_key" "protected" {
  count = var.prevent_destroy ? 1 : 0

  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = merge(var.tags, { Name = var.alias })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "unprotected" {
  count = var.prevent_destroy ? 0 : 1

  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = merge(var.tags, { Name = var.alias })
}

locals {
  key = one(concat(aws_kms_key.protected, aws_kms_key.unprotected))
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = local.key.key_id
}
