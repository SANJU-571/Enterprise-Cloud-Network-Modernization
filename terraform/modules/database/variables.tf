variable "name" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "db_sg_id" {
  type = string
}

variable "cache_sg_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "dr_kms_key_arn" {
  description = "KMS key in the DR region used to encrypt replicated backups"
  type        = string
  default     = null
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "instance_class" {
  type    = string
  default = "db.m6g.large"
}

variable "allocated_storage" {
  type    = number
  default = 100
}

variable "db_name" {
  type    = string
  default = "stratos"
}

variable "master_username" {
  type    = string
  default = "stratos_admin"
}

variable "backup_retention_days" {
  type    = number
  default = 14
}

variable "enable_cross_region_backups" {
  type    = bool
  default = true
}

variable "cache_node_type" {
  type    = string
  default = "cache.m6g.large"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
