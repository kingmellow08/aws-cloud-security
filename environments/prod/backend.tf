# Independent state for the prod environment. bucket, region, kms_key_id and
# allowed_account_ids come from the bootstrap-generated file:
#
#   terraform init -backend-config=../../backend-config/<account_id>-<region>.s3.tfbackend
#
# No credentials belong in this file or in the .tfbackend file.
terraform {
  backend "s3" {
    key          = "aws-cloud-security/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
