provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      Framework   = "aurora-postgresql-dbre"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

module "aurora_postgresql" {
  source = "../../modules/aurora_postgresql"

  cluster_identifier          = "${var.name_prefix}-aurora-pg"
  parameter_group_family      = "aurora-postgresql16"
  database_name               = var.database_name
  master_username             = var.db_master_username
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.data_subnet_ids
  allowed_security_group_ids  = var.db_allowed_security_group_ids
  allowed_cidr_blocks         = var.db_allowed_cidr_blocks
  instance_class              = var.db_instance_class
  instance_count              = var.db_instance_count
  backup_retention_period     = var.backup_retention_period
  performance_insights_retention_period = 7
  tags                        = local.common_tags
}

module "rds_proxy" {
  source = "../../modules/rds_proxy"

  proxy_name                  = "${var.name_prefix}-rds-proxy"
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.proxy_subnet_ids
  allowed_security_group_ids  = var.proxy_client_security_group_ids
  allowed_cidr_blocks         = var.proxy_client_cidr_blocks
  db_cluster_identifier       = module.aurora_postgresql.cluster_identifier
  secret_arn                  = module.aurora_postgresql.master_user_secret_arn
  db_name                     = var.database_name
  max_connections_percent     = 80
  max_idle_connections_percent = 40
  connection_borrow_timeout   = 30
  tags                        = local.common_tags
}

module "migration_control_table" {
  source = "../../modules/dynamodb"

  table_name = "${var.name_prefix}-migration-control"
  tags       = local.common_tags
}

module "elasticache_redis" {
  source = "../../modules/elasticache_redis"

  replication_group_id        = "${var.name_prefix}-redis"
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.data_subnet_ids
  allowed_security_group_ids  = var.redis_client_security_group_ids
  allowed_cidr_blocks         = var.redis_client_cidr_blocks
  node_type                   = var.redis_node_type
  engine_version              = var.redis_engine_version
  auth_token                  = var.redis_auth_token
  tags                        = local.common_tags
}
