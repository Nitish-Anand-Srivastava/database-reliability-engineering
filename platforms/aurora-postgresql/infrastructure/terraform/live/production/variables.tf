variable "aws_region" {
  description = "AWS region that hosts the database platform."
  type        = string
}

variable "environment" {
  description = "Environment name such as production or staging."
  type        = string
}

variable "name_prefix" {
  description = "Stable prefix used for resource naming."
  type        = string
}

variable "vpc_id" {
  description = "VPC identifier for all database resources."
  type        = string
}

variable "data_subnet_ids" {
  description = "Private subnet IDs for Aurora and Redis."
  type        = list(string)
}

variable "proxy_subnet_ids" {
  description = "Private subnet IDs for RDS Proxy."
  type        = list(string)
}

variable "db_allowed_security_group_ids" {
  description = "Security groups allowed to reach Aurora directly."
  type        = list(string)
  default     = []
}

variable "db_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Aurora directly."
  type        = list(string)
  default     = []
}

variable "proxy_client_security_group_ids" {
  description = "Security groups allowed to reach RDS Proxy."
  type        = list(string)
  default     = []
}

variable "proxy_client_cidr_blocks" {
  description = "CIDR blocks allowed to reach RDS Proxy."
  type        = list(string)
  default     = []
}

variable "redis_client_security_group_ids" {
  description = "Security groups allowed to reach Redis."
  type        = list(string)
  default     = []
}

variable "redis_client_cidr_blocks" {
  description = "CIDR blocks allowed to reach Redis."
  type        = list(string)
  default     = []
}

variable "database_name" {
  description = "Initial database created in the Aurora cluster."
  type        = string
  default     = "app"
}

variable "db_master_username" {
  description = "Aurora cluster master username. Password is managed by AWS Secrets Manager."
  type        = string
}

variable "db_instance_class" {
  description = "Aurora instance class."
  type        = string
  default     = "db.r7g.large"
}

variable "db_instance_count" {
  description = "Number of Aurora instances including the writer."
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Retention window for Aurora automated backups."
  type        = number
  default     = 14
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.r7g.large"
}

variable "redis_engine_version" {
  description = "Redis OSS engine version."
  type        = string
  default     = "7.1"
}

variable "redis_auth_token" {
  description = "Optional Redis auth token. Keep null only in controlled environments."
  type        = string
  sensitive   = true
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
