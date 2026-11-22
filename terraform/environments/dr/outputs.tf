output "alb_dns_name" {
  description = "Feed into prod var.dr_alb_dns_name for the Route 53 secondary record"
  value       = module.compute.alb_dns_name
}

output "alb_zone_id" {
  value = module.compute.alb_zone_id
}

output "asg_name" {
  value = module.compute.asg_name
}

output "db_subnet_group" {
  value = aws_db_subnet_group.restore.name
}

output "db_security_group_id" {
  value = module.security.db_sg_id
}
