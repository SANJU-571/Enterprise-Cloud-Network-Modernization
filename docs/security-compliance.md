# Security & Compliance

Security is layered: identity, network, data, detection and governance. Each
layer is implemented as code so it can be reviewed and audited.

## 1. Defence in depth

```mermaid
flowchart TB
    A[Identity<br/>IAM groups · MFA · SSO/AD · least privilege] --> B
    B[Perimeter<br/>WAF · FortiGate IPS · SSL-VPN + MFA · NAT] --> C
    C[Network<br/>VPC tiers · SGs · NACLs · VLANs · ACLs · 802.1X] --> D
    D[Compute<br/>IMDSv2 · SSM (no SSH keys) · patched AMIs] --> E
    E[Data<br/>KMS CMKs · TLS 1.2+ · Object Lock · backups] --> F
    F[Detection & audit<br/>CloudTrail · Config · GuardDuty · Security Hub · Flow Logs · syslog/SIEM]
```

## 2. Control matrix

| Domain | Control | Implementation |
|---|---|---|
| Identity | MFA mandatory for all humans | `EnforceMFA` policy denies everything until MFA is present |
| Identity | Least privilege, role-based groups | `ComplianceAuditor`, `DevOps`, `DataEngineer` |
| Identity | Password policy | 14+ chars, complexity, 90-day rotation, 24 reuse prevention |
| Identity | SSO / federation | AD integration through Directory Service / ISE (on-prem RADIUS) |
| Residency | Canada-only regions | SCP + IAM `aws:RequestedRegion` deny |
| Network | Tiered VPC, no public data tier | Data subnets have no default route; RDS `publicly_accessible = false` |
| Network | Firewall zoning | SG chaining ALB→app→data; FortiGate zones; explicit deny-and-log |
| Network | Secure admin access | SSM Session Manager; SSH only from IT VLAN over VPN; SSH v2 only on network gear |
| Network | Hybrid encryption | IKEv2, AES-256, SHA-256, DH20 IPsec tunnels |
| Edge | Web attacks / DDoS | AWS WAF managed rules + rate limit; Shield Standard |
| Edge | Intrusion prevention | FortiGate IPS blocks high/critical; GuardDuty in both regions |
| Data | Encryption at rest | KMS CMKs (rotation on) for RDS, EBS, S3, logs, ElastiCache, SNS |
| Data | Encryption in transit | TLS 1.3 ALB policy, `rds.force_ssl`, Redis TLS, S3 deny non-TLS |
| Data | Backup immutability | S3 Object Lock (governance, 30 days), versioning, CRR |
| Audit | API audit trail | CloudTrail multi-region with log-file validation; SCP blocks disabling it |
| Audit | Network audit | VPC Flow Logs (365 days), FortiGate + switch syslog |
| Posture | Continuous compliance | Security Hub default standards, AWS Config, Checkov in CI |
| Process | Vulnerability management | Patching through rolling ASG instance refresh; regular assessments |
| Process | Zero Trust for remote access | Identity + device posture (802.1X/ISE), MFA on VPN, per-tier authorization |

## 3. Compliance alignment

| Framework | Relevant controls here |
|---|---|
| **PIPEDA** | Residency (Canadian regions + SCP), encryption, access control, audit logs, breach-ready backups/DR |
| **SOC 2** (Security, Availability, Confidentiality) | Logical access, change management via PR + CI, monitoring/alerting, DR testing |
| **ISO 27001** Annex A | A.5 policies, A.8 asset/crypto, A.8.15 logging, A.8.20 network security, A.5.30 ICT readiness for business continuity |

## 4. Secrets handling in this repository

- No real secrets are committed. Device configs use `<REDACTED>` placeholders, and AWS secrets live in Secrets Manager (RDS-managed master password).
- `*.tfvars`, `.terraform/`, state files and key material are git-ignored.
- Checkov runs in CI against the Terraform.
