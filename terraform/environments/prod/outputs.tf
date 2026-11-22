output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "vpn_tunnel_addresses" {
  value = module.vpn.tunnel_addresses
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "backup_bucket" {
  value = module.storage.backup_bucket
}

output "sla_dashboard" {
  value = module.monitoring.dashboard_name
}
