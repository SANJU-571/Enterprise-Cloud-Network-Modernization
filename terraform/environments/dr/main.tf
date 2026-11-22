###############################################################################
# DR - ca-west-1 (Calgary), "pilot light"
#
# Always on : VPC, security groups, KMS, ALB, ASG at zero capacity
# On demand : ASG scaled up and RDS restored from the replicated automated
#             backups by scripts/dr_failover.py
#
# Targets from the infrastructure requirements report:
#   RTO < 4 hours   (measured in drills: see docs/disaster-recovery.md)
#   RPO < 15 minutes (S3 RTC 15 min + RDS replicated PITR)
###############################################################################

locals {
  name = "stratos-dr"

  tags = {
    Project     = "enterprise-cloud-network-modernization"
    Environment = "dr"
    Owner       = "cloud-infrastructure"
    DataClass   = "confidential"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  onprem_cidr        = var.onprem_cidr
  single_nat_gateway = true # cost saving while idle; switch off during a real failover
  kms_key_arn        = module.security.kms_key_arn
  tags               = local.tags
}

module "security" {
  source = "../../modules/security"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  admin_cidr         = var.admin_cidr
  enable_guardduty   = true
  enable_securityhub = false # aggregated from the primary region
  tags               = local.tags
}

module "compute" {
  source = "../../modules/compute"

  name                = local.name
  environment         = "dr"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  app_subnet_ids      = module.vpc.app_subnet_ids
  alb_sg_id           = module.security.alb_sg_id
  app_sg_id           = module.security.app_sg_id
  certificate_arn     = var.certificate_arn
  waf_acl_arn         = module.security.waf_acl_arn
  kms_key_arn         = module.security.kms_key_arn
  min_size            = 0
  desired_capacity    = 0
  max_size            = 12
  deletion_protection = true
  tags                = local.tags
}

module "vpn" {
  source = "../../modules/vpn"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  route_table_ids   = module.vpc.private_route_table_ids
  customer_gateways = var.onprem_public_ips
  onprem_bgp_asn    = 65010
  amazon_side_asn   = 64513
  tags              = local.tags
}

resource "aws_db_subnet_group" "restore" {
  name       = "${local.name}-db"
  subnet_ids = module.vpc.data_subnet_ids
  tags       = local.tags
}
