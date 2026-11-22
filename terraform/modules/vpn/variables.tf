variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "route_table_ids" {
  description = "Private route tables that should learn on-prem routes"
  type        = list(string)
}

variable "customer_gateways" {
  description = "Map of on-prem public IPs, one per ISP (e.g. { primary = \"x.x.x.x\", backup = \"y.y.y.y\" })"
  type        = map(string)
}

variable "onprem_bgp_asn" {
  type    = number
  default = 65010
}

variable "amazon_side_asn" {
  type    = number
  default = 64512
}

variable "tags" {
  type    = map(string)
  default = {}
}
