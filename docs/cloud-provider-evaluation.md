# Cloud Provider Evaluation (Canadian Data Protection)

**Recommendation: Amazon Web Services (AWS)**, with `ca-central-1` (Montreal) as
primary and `ca-west-1` (Calgary) for DR.

## 1. PIPEDA requirements that drive the decision

PIPEDA (Personal Information Protection and Electronic Documents Act) requires
personal data to be:
- collected with consent,
- stored securely (encryption at rest and in transit),
- accessed only by authorized users (identity, MFA, audit logging),
- transferred across borders only with strong safeguards. In practice that means keeping data in Canada.

It also requires a breach response: reporting, backups and recovery plans.

## 2. Comparison

| Criterion | Microsoft Azure | **AWS** | Google Cloud |
|---|---|---|---|
| Data residency in Canada | Toronto, Quebec City | **Canada Central (Montreal), Canada West (Calgary)** | Montreal, Toronto |
| Encryption at rest / in transit | AES-256 / TLS 1.2+ | AES-256 / TLS 1.2–1.3 | AES-256 / TLS 1.2+ |
| Access control | Entra ID (Azure AD), RBAC | IAM, MFA, SCPs, AD integration | IAM, VPC Service Controls |
| PIPEDA support | Yes | Yes | Yes |
| Certifications | ISO 27001, SOC 2, CSA STAR | ISO 27001/27018, SOC 1/2/3, CSA STAR, FedRAMP | ISO 27001, SOC 2, CSA STAR |
| Client-side encryption | Supported | Supported | Supported |
| Hybrid / edge | Azure Stack | Outposts, Site-to-Site VPN, Direct Connect | Anthos |

All three can meet PIPEDA. AWS was chosen for three reasons:
1. **Two Canadian regions with mature services**, so DR does not force data out of Canada.
2. **Guardrails that can be enforced in code**: SCPs, IAM region conditions, S3 Object Lock and Control Tower make residency provable, not just a policy statement.
3. **Hybrid fit** with the client's segmented on-prem network (VLANs, ASA/FortiGate, HSRP, OSPF, RADIUS).

## 3. AWS capabilities mapped to compliance

| Requirement | AWS capability | In this repo |
|---|---|---|
| Data residency | Canadian regions; SCP region deny; S3 bucket policies | `policies/scp-canada-data-residency.json`, IAM `CanadaRegionOnly` |
| Encryption | KMS CMKs (rotation on), TLS 1.3 ALB policy, RDS `force_ssl` | `modules/security` (KMS), `modules/compute`, `modules/database` |
| Key management | KMS with customer-managed keys, HSM-backed option | CMK per region |
| Access control | IAM groups/policies, MFA, AD federation | `modules/iam` |
| Logging & audit | CloudTrail (multi-region, log validation), Config, GuardDuty, Security Hub, VPC Flow Logs | `modules/iam`, `modules/security`, `modules/vpc` |
| Data sovereignty | S3 Object Lock, SCPs, Control Tower guardrails | `modules/storage`, SCP |
| Third-party review | AWS Artifact reports; supports PIAs | Annual PIA in the operating model |

## 4. Aligning AWS with the existing network

| On-prem feature | AWS equivalent |
|---|---|
| VLAN segmentation | VPC subnets, security groups, NACLs |
| ASA / FortiGate zoning | Security groups per tier, AWS WAF, (optionally) AWS Network Firewall |
| HSRP gateway redundancy | Multi-AZ ALB, Auto Scaling, RDS Multi-AZ |
| OSPF dynamic routing | BGP over Site-to-Site VPN / Direct Connect, Transit Gateway at scale |
| RADIUS / DNS / DHCP | AWS Directory Service, Route 53 (Resolver), DHCP option sets |
| NAT / PAT | NAT gateways, Elastic IPs |

## 5. Risks

| Risk | Description | Mitigation |
|---|---|---|
| Data outside Canada | A misconfigured service writes to a US region | SCP + IAM region deny, S3 bucket policies, Config rules |
| Unauthorized access | Compromised credentials, external attack | MFA enforced, least privilege, GuardDuty, WAF |
| Insufficient auditing | No visibility of who did what | CloudTrail + Config + Security Hub; an SCP stops anyone turning them off |
| Vendor lock-in | Costly to leave AWS | Terraform, open formats (PostgreSQL, Redis, S3 API), containers-ready |
| Shared-responsibility gaps | Assuming AWS secures everything | Responsibilities documented; client-side controls implemented in this repo |

## 6. IAM user model

| User / group | Purpose | Access type | MFA | Region |
|---|---|---|---|---|
| ComplianceAuditor | Audit and monitor activity | Console only (read-only) | Yes | Canada only |
| DevOps | Manage EC2, S3, ELB, monitoring | Programmatic + console | Yes | Canada only |
| DataEngineer | Read and process client data | Programmatic only | Yes | Canada only |

## 7. Phased adoption

1. **Pilot:** migrate backup storage and web applications.
2. Extend DHCP/DNS/authentication with AWS Directory Service.
3. Connect VPCs that represent departments with VPC peering / Transit Gateway.
4. Real-time monitoring with CloudWatch + SIEM.
5. Annual privacy impact assessments (PIAs).
