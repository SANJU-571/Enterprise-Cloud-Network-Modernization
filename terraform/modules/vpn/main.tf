###############################################################################
# VPN module - hybrid connectivity
# Site-to-site IPsec VPN between the AWS VGW and the on-prem edge
# (Cisco ISR / FortiGate). Two tunnels per connection, BGP for dynamic routing
# so OSPF-learned on-prem prefixes are redistributed into AWS automatically.
# A second customer gateway on the backup ISP gives ISP-level redundancy.
###############################################################################

locals {
  common_tags = merge(var.tags, { Module = "vpn" })
}

resource "aws_vpn_gateway" "this" {
  vpc_id          = var.vpc_id
  amazon_side_asn = var.amazon_side_asn

  tags = merge(local.common_tags, { Name = "${var.name}-vgw" })
}

resource "aws_customer_gateway" "this" {
  for_each   = var.customer_gateways
  bgp_asn    = var.onprem_bgp_asn
  ip_address = each.value
  type       = "ipsec.1"

  tags = merge(local.common_tags, { Name = "${var.name}-cgw-${each.key}" })
}

resource "aws_vpn_connection" "this" {
  for_each            = aws_customer_gateway.this
  vpn_gateway_id      = aws_vpn_gateway.this.id
  customer_gateway_id = each.value.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [20]
  tunnel2_phase1_dh_group_numbers      = [20]
  tunnel1_phase2_dh_group_numbers      = [20]
  tunnel2_phase2_dh_group_numbers      = [20]
  tunnel1_dpd_timeout_action           = "restart"
  tunnel2_dpd_timeout_action           = "restart"

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn.arn
      log_output_format = "json"
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn.arn
      log_output_format = "json"
    }
  }

  tags = merge(local.common_tags, { Name = "${var.name}-vpn-${each.key}" })
}

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/vpn/${var.name}"
  retention_in_days = 90
  tags              = local.common_tags
}

# Propagate on-prem routes (learned via BGP) into the private route tables
resource "aws_vpn_gateway_route_propagation" "this" {
  count          = length(var.route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = var.route_table_ids[count.index]
}
