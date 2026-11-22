variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "redis_replication_group_id" {
  type = string
}

variable "vpn_connection_ids" {
  type    = map(string)
  default = {}
}

variable "design_requests_per_target" {
  description = "Requests per target per minute that represents 100% design capacity"
  type        = number
  default     = 1000
}

variable "min_healthy_hosts" {
  type    = number
  default = 2
}

variable "health_check_fqdn" {
  type    = string
  default = ""
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "kms_key_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
