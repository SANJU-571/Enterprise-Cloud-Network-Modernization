variable "region" {
  type    = string
  default = "ca-central-1"
}

variable "dr_region" {
  type    = string
  default = "ca-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
}

variable "onprem_cidr" {
  description = "Summary route for the on-prem campus (all department VLANs)"
  type        = string
  default     = "10.10.0.0/16"
}

variable "admin_cidr" {
  description = "On-prem IT VLAN"
  type        = string
  default     = "10.10.40.0/24"
}

variable "onprem_public_ips" {
  description = "Public IPs of the on-prem edge, one per ISP"
  type        = map(string)
}

variable "certificate_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "m5.large"
}

variable "asg_min" {
  type    = number
  default = 3
}

variable "asg_max" {
  type    = number
  default = 12
}

variable "app_fqdn" {
  type    = string
  default = ""
}

variable "hosted_zone_id" {
  type    = string
  default = ""
}

variable "dr_alb_dns_name" {
  description = "Output alb_dns_name from the DR environment"
  type        = string
  default     = ""
}

variable "dr_alb_zone_id" {
  type    = string
  default = ""
}

variable "cloudtrail_bucket" {
  type    = string
  default = ""
}

variable "alert_emails" {
  type    = list(string)
  default = []
}
