# Deployment roles. Each root module has exactly one role authorised to write
# its state and manage its resources:
#
#   acs-tf-account-baseline  -> aws-cloud-security/account-baseline/terraform.tfstate
#   acs-tf-dev               -> aws-cloud-security/dev/terraform.tfstate
#   acs-tf-staging           -> aws-cloud-security/staging/terraform.tfstate
#   acs-tf-prod              -> aws-cloud-security/prod/terraform.tfstate
#
# Environment roles carry an explicit deny on every account-level security
# service, so `terraform destroy` in an environment cannot reach the baseline
# even if someone adds a stray resource block.

locals {
  baseline_name   = "${var.name_prefix}-baseline"
  boundary_arns   = { for env in local.env_scopes : env => "arn:${local.partition}:iam::${var.account_id}:policy${local.deployer_role_path}${var.name_prefix}-${env}-workload-boundary" }
  iam_arn_prefix  = "arn:${local.partition}:iam::${var.account_id}"
  protected_roots = ["account-baseline", "bootstrap"]
}

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = length(var.deployer_trusted_principal_arns) > 0 ? var.deployer_trusted_principal_arns : ["${local.iam_arn_prefix}:root"]
    }

    dynamic "condition" {
      for_each = var.require_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "deployer" {
  for_each = local.deployer_role_names

  name                 = each.value
  path                 = local.deployer_role_path
  description          = "Sole deployer for the ${each.key} Terraform root module"
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
  max_session_duration = 3600
  tags                 = { StateScope = each.key }
}

# ---------------------------------------------------------------------------
# State access: each role reads/writes only its own key and lock file.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "state_access" {
  for_each = local.state_keys

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [module.state_bucket.bucket_arn]
  }

  statement {
    sid       = "ReadWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.state_bucket.bucket_arn}/${each.value}"]
  }

  statement {
    sid       = "ManageOwnLockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.state_bucket.bucket_arn}/${each.value}.tflock"]
  }

  statement {
    sid       = "UseStateKey"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [module.state_kms.key_arn]
  }
}

resource "aws_iam_role_policy" "state_access" {
  for_each = local.state_keys

  name   = "terraform-state-${each.key}"
  role   = aws_iam_role.deployer[each.key].id
  policy = data.aws_iam_policy_document.state_access[each.key].json
}

# ---------------------------------------------------------------------------
# Guardrail shared by environment deployers and environment workload
# boundaries: nothing outside account-baseline/bootstrap may change shared
# security resources.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "protect_account_baseline" {
  statement {
    sid    = "DenyAccountSecurityServiceChanges"
    effect = "Deny"
    actions = [
      "guardduty:Create*",
      "guardduty:Delete*",
      "guardduty:Update*",
      "guardduty:Disassociate*",
      "guardduty:Stop*",
      "securityhub:Enable*",
      "securityhub:Disable*",
      "securityhub:BatchEnableStandards",
      "securityhub:BatchDisableStandards",
      "securityhub:Create*",
      "securityhub:Delete*",
      "securityhub:Update*",
      "config:Put*",
      "config:Delete*",
      "config:Start*",
      "config:Stop*",
      "cloudtrail:Create*",
      "cloudtrail:Delete*",
      "cloudtrail:Update*",
      "cloudtrail:Start*",
      "cloudtrail:Stop*",
      "cloudtrail:Put*",
      "access-analyzer:Create*",
      "access-analyzer:Delete*",
      "access-analyzer:Update*",
      "s3:PutAccountPublicAccessBlock",
      "ec2:EnableEbsEncryptionByDefault",
      "ec2:DisableEbsEncryptionByDefault",
      "ec2:ModifyEbsDefaultKmsKeyId",
      "ec2:ResetEbsDefaultKmsKeyId",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyBaselineAlertingChanges"
    effect = "Deny"
    actions = [
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:AddPermission",
      "sns:RemovePermission",
      "sns:Subscribe",
      "sns:TagResource",
      "sns:UntagResource",
      "events:PutRule",
      "events:DeleteRule",
      "events:DisableRule",
      "events:PutTargets",
      "events:RemoveTargets",
    ]
    resources = [
      "arn:${local.partition}:sns:*:${var.account_id}:${local.baseline_name}-*",
      "arn:${local.partition}:events:*:${var.account_id}:rule/${local.baseline_name}-*",
    ]
  }

  statement {
    sid    = "DenyProtectedBucketConfigChanges"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketLogging",
      "s3:PutReplicationConfiguration",
    ]
    resources = [
      "arn:${local.partition}:s3:::${local.baseline_name}-*",
      module.state_bucket.bucket_arn,
    ]
  }

  statement {
    sid       = "DenyBaselineLogObjectChanges"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["arn:${local.partition}:s3:::${local.baseline_name}-*/*"]
  }

  statement {
    sid    = "DenyProtectedKeyChanges"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:CreateGrant",
      "kms:UntagResource",
      "kms:TagResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/TerraformRoot"
      values   = local.protected_roots
    }
  }

  statement {
    sid     = "DenyProtectedAliasChanges"
    effect  = "Deny"
    actions = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = [
      "arn:${local.partition}:kms:*:${var.account_id}:alias/${local.baseline_name}-*",
      "arn:${local.partition}:kms:*:${var.account_id}:alias/${var.name_prefix}-tfstate",
    ]
  }

  statement {
    sid    = "DenyBaselineLogGroupChanges"
    effect = "Deny"
    actions = [
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:AssociateKmsKey",
      "logs:DisassociateKmsKey",
      "logs:DeleteSubscriptionFilter",
      "logs:DeleteMetricFilter",
    ]
    resources = ["arn:${local.partition}:logs:*:${var.account_id}:log-group:/${var.name_prefix}/baseline/*"]
  }

  statement {
    sid    = "DenyProtectedIamChanges"
    effect = "Deny"
    actions = [
      "iam:Create*",
      "iam:Delete*",
      "iam:Put*",
      "iam:Attach*",
      "iam:Detach*",
      "iam:Update*",
      "iam:Tag*",
      "iam:Untag*",
      "iam:SetDefaultPolicyVersion",
      "iam:PassRole",
    ]
    resources = [
      "${local.iam_arn_prefix}:role/${var.name_prefix}/baseline/*",
      "${local.iam_arn_prefix}:role${local.deployer_role_path}*",
      "${local.iam_arn_prefix}:policy${local.deployer_role_path}*",
    ]
  }
}

# ---------------------------------------------------------------------------
# account-baseline deployer
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "baseline_deployer" {
  statement {
    sid = "ManageAccountSecurityServices"
    actions = [
      "guardduty:*",
      "securityhub:*",
      "config:*",
      "cloudtrail:*",
      "access-analyzer:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageAccountWideSettings"
    actions = [
      "s3:GetAccountPublicAccessBlock",
      "s3:PutAccountPublicAccessBlock",
      "ec2:GetEbsEncryptionByDefault",
      "ec2:EnableEbsEncryptionByDefault",
      "ec2:DisableEbsEncryptionByDefault",
      "ec2:GetEbsDefaultKmsKeyId",
      "ec2:DescribeRegions",
      "organizations:DescribeOrganization",
      "organizations:ListAWSServiceAccessForOrganization",
      "organizations:ListDelegatedAdministrators",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ManageBaselineAlerting"
    actions = ["sns:*", "events:*"]
    resources = [
      "arn:${local.partition}:sns:*:${var.account_id}:${local.baseline_name}-*",
      "arn:${local.partition}:events:*:${var.account_id}:rule/${local.baseline_name}-*",
    ]
  }

  statement {
    sid       = "DiscoverAlerting"
    actions   = ["sns:ListTopics", "events:ListRules", "events:DescribeRule", "events:ListTargetsByRule", "events:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid     = "ManageBaselineBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::${local.baseline_name}-*",
      "arn:${local.partition}:s3:::${local.baseline_name}-*/*",
    ]
  }

  statement {
    sid       = "ManageBaselineLogGroups"
    actions   = ["logs:*"]
    resources = ["arn:${local.partition}:logs:*:${var.account_id}:log-group:/${var.name_prefix}/baseline/*"]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups", "logs:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateBaselineKeys"
    actions   = ["kms:CreateKey", "kms:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/TerraformRoot"
      values   = ["account-baseline"]
    }
  }

  statement {
    sid       = "ManageBaselineKeys"
    actions   = ["kms:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/TerraformRoot"
      values   = ["account-baseline"]
    }
  }

  statement {
    sid       = "ManageBaselineAliases"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${local.partition}:kms:*:${var.account_id}:alias/${local.baseline_name}-*"]
  }

  statement {
    sid       = "ListKeys"
    actions   = ["kms:ListAliases", "kms:ListKeys"]
    resources = ["*"]
  }

  statement {
    sid       = "ManageBaselineRoles"
    actions   = ["iam:*"]
    resources = ["${local.iam_arn_prefix}:role/${var.name_prefix}/baseline/*"]
  }

  statement {
    sid       = "PassBaselineRoles"
    actions   = ["iam:PassRole"]
    resources = ["${local.iam_arn_prefix}:role/${var.name_prefix}/baseline/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["config.amazonaws.com", "cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateSecurityServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "guardduty.amazonaws.com",
        "malware-protection.guardduty.amazonaws.com",
        "securityhub.amazonaws.com",
        "access-analyzer.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # The baseline owns account-level resources only; it must not be able to
  # reach into environment-owned keys, buckets or roles.
  dynamic "statement" {
    for_each = length(local.env_scopes) > 0 ? [tolist(local.env_scopes)] : []
    content {
      sid       = "DenyEnvironmentKeyChanges"
      effect    = "Deny"
      actions   = ["kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/TerraformRoot"
        values   = statement.value
      }
    }
  }
}

resource "aws_iam_role_policy" "baseline_deployer" {
  name   = "account-baseline-resources"
  role   = aws_iam_role.deployer["account-baseline"].id
  policy = data.aws_iam_policy_document.baseline_deployer.json
}

# ---------------------------------------------------------------------------
# Environment deployers (dev / staging / prod)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "env_deployer" {
  for_each = local.env_scopes

  source_policy_documents = [data.aws_iam_policy_document.protect_account_baseline.json]

  statement {
    sid       = "ManageNetworking"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid     = "ManageEnvironmentLogGroups"
    actions = ["logs:*"]
    resources = [
      "arn:${local.partition}:logs:*:${var.account_id}:log-group:/${var.name_prefix}/${each.key}/*",
    ]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups", "logs:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid       = "ManageEnvironmentAlarms"
    actions   = ["cloudwatch:*"]
    resources = ["arn:${local.partition}:cloudwatch:*:${var.account_id}:alarm:${var.name_prefix}-${each.key}-*"]
  }

  statement {
    sid       = "DescribeAlarms"
    actions   = ["cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateEnvironmentKeys"
    actions   = ["kms:CreateKey", "kms:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/TerraformRoot"
      values   = [each.key]
    }
  }

  statement {
    sid       = "ManageEnvironmentKeys"
    actions   = ["kms:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/TerraformRoot"
      values   = [each.key]
    }
  }

  statement {
    sid       = "ManageEnvironmentAliases"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${local.partition}:kms:*:${var.account_id}:alias/${var.name_prefix}-${each.key}-*"]
  }

  statement {
    sid       = "ListKeys"
    actions   = ["kms:ListAliases", "kms:ListKeys"]
    resources = ["*"]
  }

  statement {
    sid     = "ManageEnvironmentBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}-*",
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}-*/*",
    ]
  }

  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
    resources = ["*"]
  }

  # Workload roles may only be created with the environment's permissions
  # boundary, so an environment deployer cannot mint an admin role.
  statement {
    sid       = "CreateBoundedRoles"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["${local.iam_arn_prefix}:role/${var.name_prefix}/${each.key}/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arns[each.key]]
    }
  }

  statement {
    sid = "ManageEnvironmentRoles"
    actions = [
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["${local.iam_arn_prefix}:role/${var.name_prefix}/${each.key}/*"]
  }

  statement {
    sid = "ManageEnvironmentInstanceProfiles"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["${local.iam_arn_prefix}:instance-profile/${var.name_prefix}/${each.key}/*"]
  }

  statement {
    sid       = "PassEnvironmentRoles"
    actions   = ["iam:PassRole"]
    resources = ["${local.iam_arn_prefix}:role/${var.name_prefix}/${each.key}/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["vpc-flow-logs.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Read-only lookups used to verify the account baseline exists before an
  # environment is planned.
  statement {
    sid = "DiscoverAccountBaseline"
    actions = [
      "guardduty:ListDetectors",
      "guardduty:GetDetector",
      "sns:ListTopics",
      "sns:GetTopicAttributes",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(local.env_scopes) > 1 ? [[for e in local.env_scopes : e if e != each.key]] : []
    content {
      sid       = "DenyOtherEnvironmentKeys"
      effect    = "Deny"
      actions   = ["kms:*"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/TerraformRoot"
        values   = statement.value
      }
    }
  }
}

resource "aws_iam_role_policy" "env_deployer" {
  for_each = local.env_scopes

  name   = "${each.key}-environment-resources"
  role   = aws_iam_role.deployer[each.key].id
  policy = data.aws_iam_policy_document.env_deployer[each.key].json
}

# ---------------------------------------------------------------------------
# Permissions boundaries for workload roles created by each environment.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "workload_boundary" {
  for_each = local.env_scopes

  source_policy_documents = [data.aws_iam_policy_document.protect_account_baseline.json]

  statement {
    sid = "AllowWorkloadServices"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
      "cloudwatch:PutMetricData",
      "ec2:Describe*",
      "ssm:*",
      "ssmmessages:*",
      "ec2messages:*",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "AllowEnvironmentBuckets"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}-*",
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}-*/*",
    ]
  }

  statement {
    sid       = "AllowEnvironmentKeys"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/TerraformRoot"
      values   = [each.key]
    }
  }

  statement {
    sid       = "DenyIdentityManagement"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  for_each = local.env_scopes

  name        = "${var.name_prefix}-${each.key}-workload-boundary"
  path        = local.deployer_role_path
  description = "Permissions boundary for every IAM role created by the ${each.key} root module"
  policy      = data.aws_iam_policy_document.workload_boundary[each.key].json
}
