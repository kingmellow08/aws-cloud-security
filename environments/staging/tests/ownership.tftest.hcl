# Runs entirely against a mocked AWS provider: no credentials, no state
# backend, nothing created. Identical in dev, staging and prod.
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  account_id = "123456789012"
}

run "environment_owns_only_environment_resources" {
  command = apply

  assert {
    condition     = var.environment == basename(abspath(path.root))
    error_message = "terraform.tfvars environment must match the directory name."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.rejected_flows.alarm_actions) == 1
    error_message = "Environment alarms must notify the account-baseline alerts topic."
  }

  assert {
    condition     = startswith(module.data_bucket.bucket_id, "acs-${var.environment}-")
    error_message = "Environment buckets must use the acs-<env>- prefix the deployer role is scoped to."
  }

  assert {
    condition     = startswith(module.flow_logs_log_group.name, "/acs/${var.environment}/")
    error_message = "Environment log groups must live under /acs/<env>/."
  }
}

run "rejects_tfvars_from_another_environment" {
  command = plan

  variables {
    environment = run.environment_owns_only_environment_resources.environment == "dev" ? "prod" : "dev"
  }

  expect_failures = [terraform_data.environment_guard]
}

run "standalone_without_account_baseline" {
  command = apply

  variables {
    require_account_baseline = false
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.rejected_flows.alarm_actions) == 0
    error_message = "Without the baseline lookup the alarm has no shared topic to notify."
  }
}
