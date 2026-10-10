# staging configuration. Set the target account explicitly:
#   export TF_VAR_account_id=<12-digit id>
environment  = "staging"
aws_region   = "us-east-1"
project_name = "aws-cloud-security"
name_prefix  = "acs"

vpc_cidr             = "10.20.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
enable_nat_gateway   = true

# No inbound access until a load balancer is deployed and approved.
alb_ingress_cidrs = []

log_retention_days                = 90
flow_log_max_aggregation_interval = 600
kms_deletion_window_days          = 30

# staging mirrors prod topology but can be torn down deliberately.
protect_from_destroy  = false
force_destroy_buckets = false

rejected_flows_alarm_threshold = 750
