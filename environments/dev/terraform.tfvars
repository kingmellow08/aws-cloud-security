# dev configuration. Set the target account explicitly:
#   export TF_VAR_account_id=<12-digit id>
environment  = "dev"
aws_region   = "us-east-1"
project_name = "aws-cloud-security"
name_prefix  = "acs"

vpc_cidr             = "10.10.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
enable_nat_gateway   = false

# No inbound access until a load balancer is deployed and approved.
alb_ingress_cidrs = []

log_retention_days                = 30
flow_log_max_aggregation_interval = 600
kms_deletion_window_days          = 7

# dev is disposable: `terraform destroy` removes everything it owns.
protect_from_destroy  = false
force_destroy_buckets = true

rejected_flows_alarm_threshold = 1000
