variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_port" {
  description = "Port the application listens on behind the ALB"
  type        = number
  default     = 8080
}

variable "admin_cidr" {
  description = "On-prem IT/admin VLAN range allowed for SSH, metrics and DBA access over VPN"
  type        = string
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per IP before WAF blocks"
  type        = number
  default     = 2000
}

variable "enable_guardduty" {
  type    = bool
  default = true
}

variable "enable_securityhub" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
