###############################################################################
# Production - ca-central-1 (Montreal), DR in ca-west-1 (Calgary)
# Both regions are in Canada, so data residency (PIPEDA) holds even during
# a regional failover.
###############################################################################

locals {
  name = "stratos-prod"

  tags = {
    Project     = "enterprise-cloud-network-modernization"
    Environment = "prod"
    Owner       = "cloud-infrastructure"
    DataClass   = "confidential"
    ManagedBy   = "terraform"
  }
}

# DR-region KMS key (needed by S3 CRR and RDS backup replication)
resource "aws_kms_key" "dr" {
  provider                = aws.dr
  description             = "${local.name} DR-region key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  onprem_cidr        = var.onprem_cidr
  kms_key_arn        = module.security.kms_key_arn
  tags               = local.tags
}

module "security" {
  source = "../../modules/security"

  name       = local.name
  vpc_id     = module.vpc.vpc_id
  admin_cidr = var.admin_cidr
  tags       = local.tags
}

module "storage" {
  source = "../../modules/storage"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name           = local.name
  kms_key_arn    = module.security.kms_key_arn
  dr_kms_key_arn = aws_kms_key.dr.arn
  tags           = local.tags
}

module "database" {
  source = "../../modules/database"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name            = local.name
  data_subnet_ids = module.vpc.data_subnet_ids
  db_sg_id        = module.security.db_sg_id
  cache_sg_id     = module.security.cache_sg_id
  kms_key_arn     = module.security.kms_key_arn
  dr_kms_key_arn  = aws_kms_key.dr.arn
  tags            = local.tags
}

module "compute" {
  source = "../../modules/compute"

  name              = local.name
  environment       = "prod"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  app_subnet_ids    = module.vpc.app_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  app_sg_id         = module.security.app_sg_id
  certificate_arn   = var.certificate_arn
  waf_acl_arn       = module.security.waf_acl_arn
  kms_key_arn       = module.security.kms_key_arn
  instance_type     = var.instance_type
  min_size          = var.asg_min
  max_size          = var.asg_max
  desired_capacity  = var.asg_min
  redis_endpoint    = module.database.redis_primary_endpoint
  db_secret_arn     = module.database.db_master_secret_arn
  access_log_bucket = module.storage.log_bucket
  tags              = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name              = local.name
  data_bucket_arn   = module.storage.backup_bucket_arn
  kms_key_arn       = module.security.kms_key_arn
  cloudtrail_bucket = var.cloudtrail_bucket
  tags              = local.tags
}

module "vpn" {
  source = "../../modules/vpn"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  route_table_ids   = module.vpc.private_route_table_ids
  customer_gateways = var.onprem_public_ips
  tags              = local.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                       = local.name
  region                     = var.region
  alb_arn_suffix             = module.compute.alb_arn_suffix
  target_group_arn_suffix    = module.compute.target_group_arn_suffix
  db_identifier              = module.database.db_identifier
  redis_replication_group_id = module.database.redis_replication_group_id
  vpn_connection_ids         = module.vpn.vpn_connection_ids
  health_check_fqdn          = var.app_fqdn
  alert_emails               = var.alert_emails
  kms_key_arn                = module.security.kms_key_arn
  min_healthy_hosts          = length(var.availability_zones)
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# DNS failover: primary record -> prod ALB, secondary -> DR ALB.
# Route 53 flips automatically when the health check fails.
# ---------------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  count           = var.hosted_zone_id == "" ? 0 : 1
  zone_id         = var.hosted_zone_id
  name            = var.app_fqdn
  type            = "A"
  set_identifier  = "primary-ca-central-1"
  health_check_id = module.monitoring.health_check_id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = module.compute.alb_dns_name
    zone_id                = module.compute.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count          = var.hosted_zone_id == "" || var.dr_alb_dns_name == "" ? 0 : 1
  zone_id        = var.hosted_zone_id
  name           = var.app_fqdn
  type           = "A"
  set_identifier = "secondary-ca-west-1"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.dr_alb_dns_name
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}
