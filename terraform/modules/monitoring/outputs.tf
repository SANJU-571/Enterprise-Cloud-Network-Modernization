output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.sla.dashboard_name
}

output "health_check_id" {
  value = try(aws_route53_health_check.app[0].id, null)
}
