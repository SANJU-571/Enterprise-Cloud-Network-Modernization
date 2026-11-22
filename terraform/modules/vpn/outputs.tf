output "vpn_gateway_id" {
  value = aws_vpn_gateway.this.id
}

output "vpn_connection_ids" {
  value = { for k, v in aws_vpn_connection.this : k => v.id }
}

output "tunnel_addresses" {
  description = "AWS-side tunnel endpoints to configure on the on-prem edge"
  value = {
    for k, v in aws_vpn_connection.this : k => {
      tunnel1 = v.tunnel1_address
      tunnel2 = v.tunnel2_address
    }
  }
}
