variable "region" {
  type    = string
  default = "ca-west-1"
}

variable "vpc_cidr" {
  description = "Must not overlap prod (10.20.0.0/16) or on-prem (10.10.0.0/16)"
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ca-west-1a", "ca-west-1b", "ca-west-1c"]
}

variable "onprem_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "admin_cidr" {
  type    = string
  default = "10.10.40.0/24"
}

variable "onprem_public_ips" {
  type = map(string)
}

variable "certificate_arn" {
  type = string
}
