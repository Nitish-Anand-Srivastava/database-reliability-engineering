variable "replication_group_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

variable "node_type" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "auth_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.replication_group_id}-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.replication_group_id}-sg"
  description = "ElastiCache Redis access"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.replication_group_id}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Redis access from approved security groups"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
  description       = "Redis access from approved CIDR blocks"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = var.replication_group_id
  description                = "Redis cache for Aurora-adjacent workloads"
  node_type                  = var.node_type
  port                       = 6379
  engine                     = "redis"
  engine_version             = var.engine_version
  parameter_group_name       = "default.redis7"
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.this.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
  num_node_groups            = 1
  replicas_per_node_group    = 1
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_token
  apply_immediately          = false

  tags = merge(var.tags, {
    Name = var.replication_group_id
  })
}

output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  value = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "security_group_id" {
  value = aws_security_group.this.id
}
