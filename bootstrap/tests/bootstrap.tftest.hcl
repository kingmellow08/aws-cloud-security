# Runs against mocked providers: no credentials, nothing created, and the
# backend-config file is not written.
#   terraform init && terraform test

mock_provider "aws" {
  source = "../tests/mocks"
}

mock_provider "local" {}

variables {
  account_id = "123456789012"
}

run "single_account_layout" {
  command = apply

  assert {
    condition = output.state_keys == {
      account-baseline = "aws-cloud-security/account-baseline/terraform.tfstate"
      dev              = "aws-cloud-security/dev/terraform.tfstate"
      staging          = "aws-cloud-security/staging/terraform.tfstate"
      prod             = "aws-cloud-security/prod/terraform.tfstate"
    }
    error_message = "State keys must match the key in each root module's backend.tf."
  }

  assert {
    condition     = length(aws_iam_role.deployer) == 4 && length(aws_iam_policy.workload_boundary) == 3
    error_message = "One deployer per root and one workload boundary per environment."
  }

  assert {
    condition     = local.state_bucket_name == "acs-tfstate-123456789012-us-east-1"
    error_message = "State bucket name must embed the account ID and Region."
  }

  assert {
    condition     = endswith(local_file.backend_config.filename, "backend-config/123456789012-us-east-1.s3.tfbackend")
    error_message = "Backend config file name must be <account_id>-<region>.s3.tfbackend."
  }
}

run "multi_account_production_account" {
  command = apply

  variables {
    state_scopes = ["account-baseline", "prod"]
  }

  assert {
    condition     = keys(aws_iam_role.deployer) == ["account-baseline", "prod"]
    error_message = "Only the scopes hosted in this account get deployer roles."
  }
}

run "every_account_requires_a_baseline" {
  command = plan

  variables {
    state_scopes = ["dev"]
  }

  expect_failures = [var.state_scopes]
}
