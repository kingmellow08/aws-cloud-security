locals {
  default_tags = {
    Project       = var.project_name
    TerraformRoot = "account-baseline"
    StateKey      = "${var.project_name}/account-baseline/terraform.tfstate"
    Lifecycle     = "long-lived"
    ManagedBy     = "terraform"
  }
}

# Home Region: CloudTrail, Config global resource recording, Security Hub
# CSPM finding aggregation, alerting and account-wide settings live here.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}

# Optional second Region for regional services (GuardDuty, Security Hub CSPM,
# Config, EBS default encryption). When secondary_region is null the alias
# points at the home Region and no secondary modules are instantiated.
provider "aws" {
  alias               = "secondary"
  region              = coalesce(var.secondary_region, var.aws_region)
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}
