# Hybrid Deployment Guide

A step-by-step build of the hybrid environment: the AWS side through Terraform,
then the on-premises hardware. It was written for a 100-employee, two-location
software company (the reference build), and the same steps scale to the
300-user campus.

## Part A: AWS (Terraform)

### Prerequisites
- Terraform ≥ 1.6, AWS CLI v2, credentials for the target account (MFA session)
- ACM certificates in `ca-central-1` and `ca-west-1`
- Public IPs of both on-prem internet edges

### A0. Bootstrap state (once)
```bash
./scripts/bootstrap_state.sh          # S3 bucket + DynamoDB lock table
```

### A1. DR region first (pilot light)
```bash
cd terraform/environments/dr
cp terraform.tfvars.example terraform.tfvars   # fill in
terraform init && terraform plan -out tfplan && terraform apply tfplan
terraform output alb_dns_name alb_zone_id       # needed by prod
```

### A2. Production
```bash
cd ../prod
cp terraform.tfvars.example terraform.tfvars   # paste DR ALB outputs
terraform init && terraform plan -out tfplan && terraform apply tfplan
terraform output vpn_tunnel_addresses           # for the on-prem edge
```

What gets created, in dependency order:

| # | Component | Module | Notes |
|---|---|---|---|
| 1 | VPC, 3-tier subnets × 3 AZs, IGW, NAT per AZ, flow logs, S3 endpoint | `vpc` | Public = web, private = app/DB |
| 2 | KMS CMK, security groups, WAF, GuardDuty, Security Hub | `security` | Only 443 exposed publicly |
| 3 | S3 backup bucket (versioned, Object Lock, lifecycle) + DR replica + ALB log bucket | `storage` | CRR with 15-min RTC |
| 4 | RDS PostgreSQL Multi-AZ + ElastiCache Redis | `database` | Encrypted, backups replicated to DR |
| 5 | ALB + Auto Scaling group across AZs | `compute` | Scales on CPU and requests per target |
| 6 | IAM groups, MFA and region guardrails, CloudTrail | `iam` | Least privilege |
| 7 | VPN gateway, 2 customer gateways, 4 IPsec tunnels, route propagation | `vpn` | BGP dynamic routing |
| 8 | SNS, SLA alarms, dashboard, Route 53 health check | `monitoring` | Feeds the NOC |
| 9 | Route 53 failover records | prod `main.tf` | Primary → prod ALB, secondary → DR ALB |

## Part B: On-premises hardware

| Step | Device | Actions | Config |
|---|---|---|---|
| B1 | **Racks, patch panels, UPS** | Mount gear in 19" racks, label every port, structured cabling, UPS with graceful-shutdown agents on servers | — |
| B2 | **Cisco ISR (edge router)** | Connect ISP-1, NAT/PAT, IP SLA tracking, QoS; build IPsec VTIs to the AWS tunnel IPs; BGP AS 65010 | `network/cisco/edge-isr-4331.cfg` |
| B3 | **FortiGate NGFW** | Behind the router; zones, IPS, web filter, AV; ISP-2 on WAN2 with SD-WAN failover | `network/fortigate/edge-fw.conf` |
| B4 | **VPN for remote staff + AD** | SSL-VPN (or IPsec) with RADIUS/AD groups and FortiToken MFA; split tunnelling where bandwidth matters | `edge-fw.conf` (SSL-VPN section) |
| B5 | **Layer 3 core pair** | VLANs per department, SVIs with HSRP, OSPF, ACLs, port security | `network/cisco/core-sw1.cfg`, `core-sw2.cfg` |
| B6 | **Access switches** | LACP uplinks to both cores, 802.1X/MAB, L2 security features | `network/cisco/access-sales-01.cfg` |
| B7 | **Wi-Fi 6 access points** | PoE+ trunks, SSIDs per VLAN, WPA3, guest isolation | `network/wireless/ap-plan.yaml` |
| B8 | **Local servers** | AD domain controllers (DNS/DHCP), RADIUS/ISE, print, app caching | `network/addressing/vlans.yaml` (servers) |
| B9 | **NAS** | SMB shares, daily local backups, nightly sync to the S3 backup bucket over the VPN | — |
| B10 | **Monitoring stack** | Prometheus, Alertmanager, blackbox, SNMP exporter, Grafana | `monitoring/docker-compose.yml` |
| B11 | **On-prem LB pair** | HAProxy + keepalived VIP for internal apps; NGINX reverse proxy in the DMZ | `load-balancer/` |

## Part C: Verify end to end

```bash
# Hybrid routing
show ip bgp summary                     # on EDGE-ISR: both AWS neighbours Established
aws ec2 describe-route-tables ...       # 10.10.0.0/16 propagated via VGW

# Performance against targets
python scripts/network_perf.py --host 10.20.64.10           # on-prem -> AWS app tier
python scripts/validate_network.py                          # plan/config consistency

# SLA
python scripts/sla_report.py data/target-state-metrics.json
```

## Summary

| Goal | Solution |
|---|---|
| Secure remote work | SSL-VPN + MFA, IAM roles for cloud users, FortiGate perimeter, MFA everywhere |
| Performance & scaling | EC2 Auto Scaling + ALB in the cloud; L3 switching + QoS on-prem; Redis caching |
| High availability | RDS Multi-AZ, ASG across AZs, HSRP, LACP, dual ISP, UPS |
| Disaster recovery | RDS PITR replicated to DR, S3 CRR, NAS → S3 sync, Route 53 failover |
| Cost-effective scale | Pay-per-use Auto Scaling, pilot-light DR, S3 lifecycle tiering |
