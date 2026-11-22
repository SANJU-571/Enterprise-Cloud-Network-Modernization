output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "cache_sg_id" {
  value = aws_security_group.cache.id
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}
