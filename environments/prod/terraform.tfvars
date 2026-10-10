# prod configuration. Set the target account explicitly:
#   export TF_VAR_account_id=<12-digit id>
environment  = "prod"
aws_region   = "us-east-1"
project_name = "aws-cloud-security"
name_prefix  = "acs"

vpc_cidr             = "10.30.0.0/16"
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]
enable_nat_gateway   = true

# No inbound access until a load balancer is deployed and approved.
alb_ingress_cidrs = []

log_retention_days                = 365
flow_log_max_aggregation_interval = 60
kms_deletion_window_days          = 30

# prod data, keys and logs survive `terraform destroy` (see the cleanup
# procedure in docs/terraform-state-ownership.md).
protect_from_destroy  = true
force_destroy_buckets = false

rejected_flows_alarm_threshold = 500
