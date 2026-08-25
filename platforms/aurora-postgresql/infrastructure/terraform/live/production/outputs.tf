output "aurora_cluster_endpoint" {
  description = "Aurora writer endpoint."
  value       = module.aurora_postgresql.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint."
  value       = module.aurora_postgresql.reader_endpoint
}

output "aurora_master_secret_arn" {
  description = "AWS-managed secret that stores the Aurora master password."
  value       = module.aurora_postgresql.master_user_secret_arn
  sensitive   = true
}

output "rds_proxy_endpoint" {
  description = "Primary RDS Proxy endpoint for application traffic."
  value       = module.rds_proxy.endpoint
}

output "dynamodb_table_name" {
  description = "DynamoDB table that stores migration coordination state."
  value       = module.migration_control_table.table_name
}

output "redis_primary_endpoint" {
  description = "Primary endpoint for ElastiCache Redis."
  value       = module.elasticache_redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Reader endpoint for ElastiCache Redis."
  value       = module.elasticache_redis.reader_endpoint_address
}
