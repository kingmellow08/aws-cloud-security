# Non-secret bootstrap settings. account_id is intentionally not set here:
# export TF_VAR_account_id=<12-digit id> for the account you are bootstrapping
# so the target account is always an explicit choice.
aws_region   = "us-east-1"
project_name = "aws-cloud-security"
name_prefix  = "acs"

# Single-account layout: all four remote-state roots share this bucket.
# In a multi-account layout, bootstrap each account with only the scopes it
# hosts, e.g. ["account-baseline", "prod"] in the production account.
state_scopes = ["account-baseline", "dev", "staging", "prod"]

# Restrict to your SSO permission-set role(s) and/or CI OIDC role in practice.
deployer_trusted_principal_arns = []
require_mfa                     = true
break_glass_principal_arns      = []
