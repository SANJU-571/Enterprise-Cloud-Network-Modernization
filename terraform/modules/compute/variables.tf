variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "app_sg_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener"
  type        = string
}

variable "waf_acl_arn" {
  type    = string
  default = ""
}

variable "kms_key_arn" {
  type = string
}

variable "ami_id" {
  description = "Override AMI (defaults to latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "m5.large baseline; m5.xlarge is the vertical scaling step from the action plan"
  type        = string
  default     = "m5.large"
}

variable "min_size" {
  description = "Minimum instances - keep >= number of AZs so every AZ always has capacity"
  type        = number
  default     = 3
}

variable "max_size" {
  type    = number
  default = 12
}

variable "desired_capacity" {
  type    = number
  default = 3
}

variable "cpu_target" {
  description = "Target average CPU % for the ASG"
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Target ALB requests per instance per minute"
  type        = number
  default     = 1000
}

variable "redis_endpoint" {
  type    = string
  default = ""
}

variable "db_secret_arn" {
  type    = string
  default = ""
}

variable "access_log_bucket" {
  type    = string
  default = ""
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
