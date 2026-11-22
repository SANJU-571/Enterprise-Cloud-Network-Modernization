###############################################################################
# Monitoring module - SLA-driven alerting (action plan task 3.2)
#
#   SLA                          | Early-warning alarm in this module
#   -----------------------------|-------------------------------------------
#   Uptime >= 99.5%              | Route 53 health check fails / HealthyHosts < min
#   Response <= 200 ms (p95)     | ALB TargetResponseTime p95 > 180 ms for 5 min
#   LB capacity <= 85%           | RequestCountPerTarget > 80% of design for 10 min
#   Errors <= 10 / day           | HTTPCode_Target_5XX sum > 10 over 24 h
#   Inter-region latency <=100ms | (measured on-prem by Prometheus blackbox)
###############################################################################

locals {
  common_tags = merge(var.tags, { Module = "monitoring" })

  alb_dims = {
    LoadBalancer = var.alb_arn_suffix
  }
  tg_dims = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-sla-alerts"
  kms_master_key_id = var.kms_key_arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Response time - p95 early warning at 180 ms (SLA is 200 ms)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-sla-latency-p95"
  alarm_description   = "p95 target response time above 180 ms for 5 minutes (SLA 200 ms)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  dimensions          = local.alb_dims
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 0.18
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Load balancer capacity proxy - requests per target vs design capacity
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lb_capacity" {
  alarm_name          = "${var.name}-sla-lb-capacity"
  alarm_description   = "Requests per target above 80% of design capacity for 10 minutes (SLA <= 85%)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCountPerTarget"
  statistic           = "Sum"
  dimensions          = local.tg_dims
  period              = 60
  evaluation_periods  = 10
  threshold           = var.design_requests_per_target * 0.80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Error budget - more than 10 backend 5xx in 24h
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "errors_daily" {
  alarm_name          = "${var.name}-sla-errors-daily"
  alarm_description   = "More than 10 target 5xx errors in 24 hours (SLA <= 10/day)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  dimensions          = local.alb_dims
  period              = 86400
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Availability - healthy hosts and external health check
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  alarm_name          = "${var.name}-healthy-hosts-low"
  alarm_description   = "Healthy targets below minimum - capacity at risk"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  dimensions          = local.tg_dims
  period              = 60
  evaluation_periods  = 2
  threshold           = var.min_healthy_hosts
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

resource "aws_route53_health_check" "app" {
  count             = var.health_check_fqdn == "" ? 0 : 1
  fqdn              = var.health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/healthz"
  failure_threshold = 3
  request_interval  = 10
  measure_latency   = true
  regions           = ["us-east-1", "us-west-2", "eu-west-1"]

  tags = merge(local.common_tags, { Name = "${var.name}-app-health" })
}

# ---------------------------------------------------------------------------
# Database & cache
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu-high"
  alarm_description   = "RDS CPU above 70% for 10 minutes (action plan threshold)"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  period              = 60
  evaluation_periods  = 10
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name}-rds-free-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  period              = 300
  evaluation_periods  = 1
  threshold           = 10 * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cache_hit_ratio" {
  alarm_name          = "${var.name}-redis-hit-ratio-low"
  alarm_description   = "Cache hit ratio below 80% - DB load and latency will rise"
  namespace           = "AWS/ElastiCache"
  metric_name         = "CacheHitRate"
  statistic           = "Average"
  dimensions          = { ReplicationGroupId = var.redis_replication_group_id }
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# VPN tunnel state (hybrid connectivity)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "vpn_down" {
  for_each            = var.vpn_connection_ids
  alarm_name          = "${var.name}-vpn-${each.key}-down"
  alarm_description   = "Both tunnels of VPN ${each.key} down"
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  statistic           = "Maximum"
  dimensions          = { VpnId = each.value }
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# SLA dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "sla" {
  dashboard_name = "${var.name}-sla"
  dashboard_body = templatefile("${path.module}/dashboard.json.tftpl", {
    region       = var.region
    alb          = var.alb_arn_suffix
    tg           = var.target_group_arn_suffix
    db           = var.db_identifier
    redis        = var.redis_replication_group_id
    design_rpt   = var.design_requests_per_target
    latency_line = 0.2
  })
}
