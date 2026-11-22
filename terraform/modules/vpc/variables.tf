variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (a /16 is expected)"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "AZs to spread subnets across (minimum 2 for HA)"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for high availability."
  }
}

variable "onprem_cidr" {
  description = "On-premises network range reachable over the site-to-site VPN"
  type        = string
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway instead of one per AZ (cost saving for non-prod / DR pilot light)"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs"
  type        = number
  default     = 365
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt log groups"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
