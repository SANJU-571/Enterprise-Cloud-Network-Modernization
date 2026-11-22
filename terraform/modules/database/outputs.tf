output "db_endpoint" {
  value = aws_db_instance.primary.address
}

output "db_identifier" {
  value = aws_db_instance.primary.identifier
}

output "db_arn" {
  value = aws_db_instance.primary.arn
}

output "db_master_secret_arn" {
  value = aws_db_instance.primary.master_user_secret[0].secret_arn
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.redis.id
}
