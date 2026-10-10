provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project       = var.project_name
      Environment   = var.environment
      TerraformRoot = var.environment
      StateKey      = "${var.project_name}/${var.environment}/terraform.tfstate"
      ManagedBy     = "terraform"
    }
  }
}
