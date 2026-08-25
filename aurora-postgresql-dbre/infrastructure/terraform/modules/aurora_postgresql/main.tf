variable "cluster_identifier" {
  type = string
}

variable "parameter_group_family" {
  type = string
}

variable "database_name" {
  type = string
}

variable "master_username" {
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

variable "instance_class" {
  type = string
}

variable "instance_count" {
  type = number
}

variable "backup_retention_period" {
  type = number
}

variable "performance_insights_retention_period" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_identifier}-subnets"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.cluster_identifier}-sg"
  description = "Aurora PostgreSQL access"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_identifier}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL access from approved security groups"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL access from approved CIDR blocks"
}

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.cluster_identifier}-cluster-pg"
  family = var.parameter_group_family

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "pg_stat_statements.max"
    value = "10000"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }

  parameter {
    name  = "track_io_timing"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "lock_timeout"
    value = "2000"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "60000"
  }

  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }

  tags = var.tags
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = var.cluster_identifier
  engine                              = "aurora-postgresql"
  engine_version                      = "16.4"
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.this.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  storage_encrypted                   = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "sun:04:00-sun:05:00"
  deletion_protection                 = true
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  apply_immediately                   = false

  tags = var.tags
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier                           = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier                   = aws_rds_cluster.this.id
  instance_class                       = var.instance_class
  engine                               = aws_rds_cluster.this.engine
  engine_version                       = aws_rds_cluster.this.engine_version
  db_subnet_group_name                 = aws_db_subnet_group.this.name
  performance_insights_enabled         = true
  performance_insights_retention_period = var.performance_insights_retention_period
  auto_minor_version_upgrade           = false
  copy_tags_to_snapshot                = true
  promotion_tier                       = count.index == 0 ? 0 : count.index
  publicly_accessible                  = false

  tags = merge(var.tags, {
    Role = count.index == 0 ? "writer-candidate" : "reader-candidate"
  })
}

output "cluster_identifier" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "master_user_secret_arn" {
  value = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}
