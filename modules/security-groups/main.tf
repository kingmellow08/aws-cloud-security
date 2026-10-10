# Three-tier security groups. Every rule references another group or an
# explicit CIDR; nothing allows 0.0.0.0/0 inbound.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer tier: HTTPS from approved CIDRs only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb", Tier = "alb" })
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Application tier: traffic from the load balancer only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-app", Tier = "app" })
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Database tier: traffic from the application tier only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-db", Tier = "db" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to application tier"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From load balancer tier"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs and package mirrors"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "To database tier"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "From application tier"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.app.id
}
