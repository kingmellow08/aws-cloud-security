# State for account-level security services. Exactly one account-baseline
# state exists per AWS account. bucket, region, kms_key_id and
# allowed_account_ids are supplied at init time from the file bootstrap
# generates:
#
#   terraform init -backend-config=../backend-config/<account_id>-<region>.s3.tfbackend
#
# No credentials belong in this file or in the .tfbackend file.
terraform {
  backend "s3" {
    key          = "aws-cloud-security/account-baseline/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
