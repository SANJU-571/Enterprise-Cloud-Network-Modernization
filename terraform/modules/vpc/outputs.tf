output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "app_subnet_cidrs" {
  value = aws_subnet.app[*].cidr_block
}

output "private_route_table_ids" {
  description = "Route tables that should receive VPN-propagated routes"
  value       = concat(aws_route_table.app[*].id, [aws_route_table.data.id])
}

output "nat_public_ips" {
  value = aws_eip.nat[*].public_ip
}
