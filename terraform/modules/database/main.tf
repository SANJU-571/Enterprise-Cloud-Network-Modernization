###############################################################################
# Database module
#   * RDS PostgreSQL Multi-AZ (synchronous standby, automatic failover)
#   * Automated backups replicated to the DR region (RPO < 15 min target)
#   * Optional cross-region read replica that can be promoted during DR
#   * ElastiCache Redis (Multi-AZ, automatic failover) for the cache-aside
#     layer that brings response times under the 200 ms SLA
###############################################################################

locals {
  common_tags = merge(var.tags, { Module = "database" })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.data_subnet_ids
  tags       = local.common_tags
}

resource "aws_db_parameter_group" "pg" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  # Surface slow queries (action plan task 1.2: top-10 slowest queries)
  parameter {
    name  = "log_min_duration_statement"
    value = "200"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = local.common_tags
}

resource "aws_db_instance" "primary" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 4
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  parameter_group_name   = aws_db_parameter_group.pg.name
  publicly_accessible    = false

  backup_retention_period  = var.backup_retention_days
  backup_window            = "06:00-07:00" # 01:00-02:00 Toronto (EST)
  maintenance_window       = "sun:07:30-sun:08:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 15
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.name}-pg-final"

  tags = merge(local.common_tags, { Name = "${var.name}-pg" })
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Cross-region automated backup replication (PITR in the DR region)
# ---------------------------------------------------------------------------
resource "aws_db_instance_automated_backups_replication" "dr" {
  count    = var.enable_cross_region_backups ? 1 : 0
  provider = aws.dr

  source_db_instance_arn = aws_db_instance.primary.arn
  kms_key_id             = var.dr_kms_key_arn
  retention_period       = var.backup_retention_days
}

# ---------------------------------------------------------------------------
# ElastiCache Redis - cache-aside for hot read paths
# ---------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-cache"
  subnet_ids = var.data_subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name}-redis"
  description          = "Cache-aside layer for application read paths"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.cache_node_type
  port                 = 6379

  num_cache_clusters         = length(var.data_subnet_ids)
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.cache_sg_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn

  snapshot_retention_limit = 3
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "sun:08:30-sun:09:30"

  tags = local.common_tags
}
