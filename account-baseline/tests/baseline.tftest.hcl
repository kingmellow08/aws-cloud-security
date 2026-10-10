# Runs against mocked providers: no credentials, no backend, nothing created.
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  source = "../tests/mocks"
}

mock_provider "aws" {
  alias  = "secondary"
  source = "../tests/mocks"
}

variables {
  account_id = "123456789012"
}

run "single_region_baseline" {
  command = apply

  assert {
    condition     = length(module.guardduty_secondary) == 0 && length(module.securityhub_secondary) == 0 && length(module.config_secondary) == 0
    error_message = "No secondary-Region services without secondary_region."
  }

  assert {
    condition     = length(aws_securityhub_finding_aggregator.this) == 0
    error_message = "No finding aggregator without a linked Region."
  }

  assert {
    condition     = output.security_alerts_topic_name == "acs-baseline-security-alerts"
    error_message = "Environments look the alerts topic up by this exact name."
  }

  assert {
    condition     = alltrue([for name in keys(module.config_home.config_rule_arns) : startswith(name, "acs-baseline-")])
    error_message = "Config rules must carry the acs-baseline- prefix."
  }
}

run "secondary_region_via_provider_alias" {
  command = apply

  variables {
    secondary_region = "us-west-2"
  }

  assert {
    condition     = length(module.guardduty_secondary) == 1 && length(module.securityhub_secondary) == 1 && length(module.config_secondary) == 1
    error_message = "Regional services must be enabled in the secondary Region."
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].specified_regions == toset(["us-west-2"])
    error_message = "Secondary Region findings must aggregate into the home Region."
  }

  assert {
    condition     = length(output.guardduty_detector_ids) == 2
    error_message = "One GuardDuty detector per Region."
  }
}
