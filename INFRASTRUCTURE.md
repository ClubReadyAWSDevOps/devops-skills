# ClubReady AWS Infrastructure Reference

This document provides infrastructure-specific context for using the DevOps skills in this repository.

## AWS Account Structure

| Account | ID | Purpose | Access Method |
|---------|-------|---------|---------------|
| Management | TBD | AWS Organizations, billing, centralized logging | IAM Identity Center |
| Production | TBD | Production workloads (RDS, ECS, S3) | IAM Identity Center + OIDC |
| Staging | TBD | Pre-production testing | IAM Identity Center + OIDC |
| Development | TBD | Development workloads | IAM Identity Center |

## Primary AWS Services

### Compute
- **ECS Fargate** (ARM64 Graviton preferred)
  - Cluster: `app-prod`, `app-staging`
  - Services: `portal`, `delayed-jobs`, `llm-orchestrator`, `reporting`, `api`
- **Lambda** (for async tasks, Step Functions)

### Database
- **RDS Aurora PostgreSQL** (Multi-AZ, r6g/r7g Graviton instances)
  - Production: `app-prod` cluster
  - Staging: `app-staging` cluster
  - QA: `app-qa` cluster
- **Redis/Valkey** (ElastiCache) — sessions, cache, background jobs
- **DynamoDB** — ClubReady raw data (partitioned by `clubready_store_id`)

### Storage
- **S3** — application assets, backups, Data Bridge exports
  - Lifecycle policies: transition to Glacier after 90 days
  - Versioning enabled on critical buckets
- **EBS** — persistent volumes (encrypted at rest)

### Networking
- **VPC** (us-west-2)
  - Public subnets: ALBs only
  - Private subnets: ECS tasks, RDS, ElastiCache
  - Isolated subnets: No internet access (future use)
- **ALB** — HTTPS termination, path-based routing

### Monitoring & Logging
- **CloudWatch Logs** — application logs, RDS query logs
- **CloudWatch Metrics** — custom metrics, dashboards
- **CloudWatch Alarms** — CPU, memory, 5xx errors, database connections
- **VPC Flow Logs** — network traffic analysis

### Security
- **AWS Secrets Manager** — RDS passwords, API keys (rotation enabled)
- **IAM Identity Center** — human user SSO
- **IAM Roles** — service-to-service, GitHub Actions OIDC
- **Security Groups** — least-privilege network rules
- **GuardDuty** — threat detection

### CI/CD
- **GitHub Actions** — automated builds, tests, deployments
- **ECR** — private Docker image registry (ARM64 images)
- **Terraform** — infrastructure-as-code (S3 backend + DynamoDB locks)

## Default Configuration

All skills assume:
- **Region:** `us-west-2` (explicit `--region us-west-2` in all CLI commands)
- **Profile:** No `--profile` flag (use `AWS_PROFILE` env var or default profile)
- **IAM Auth:** RDS uses IAM tokens via `rds-db:connect` (read-only user: `iam_user_ro`)

## Cost Structure

Approximate monthly spend (Production):

| Service | Monthly Cost | % of Total |
|---------|-------------|-----------|
| RDS Aurora | $4,500 | 38% |
| ECS Fargate | $3,200 | 27% |
| Data Transfer | $1,800 | 15% |
| S3 + Glacier | $900 | 8% |
| ElastiCache | $700 | 6% |
| Other (CloudWatch, Secrets Manager, etc.) | $700 | 6% |
| **Total** | **$11,800** | **100%** |

## Architecture Patterns

### High Availability
- All RDS clusters: Multi-AZ with 2+ read replicas
- ECS services: Minimum 2 tasks across 2 AZs
- ALBs: Cross-zone load balancing enabled
- S3: Versioning + cross-region replication for critical buckets

### Disaster Recovery
- RDS automated backups: 7-day retention
- Manual snapshots: Monthly (kept for 1 year)
- Terraform state: S3 versioning enabled
- RTO: 1 hour (Aurora failover ~60s, ECS redeploy ~5m)
- RPO: 15 minutes (RDS transaction log shipping)

### Security Model
- Zero trust: All traffic between services uses IAM authentication where possible
- Secrets never in env vars: Use Secrets Manager + IAM permissions
- Principle of least privilege: IAM roles scoped to specific resources
- Encryption: At rest (RDS, S3, EBS) and in transit (TLS 1.2+)

### Cost Optimization
- Graviton adoption: 85% of compute workloads on ARM64
- Reserved capacity: 80% of production RDS on 1-year RIs
- Spot instances: None (prefer predictable costs for production)
- Lifecycle policies: Auto-archive old S3 objects to Glacier

## Tagging Strategy

All resources must have:
- `Environment` (production, staging, development)
- `Project` (ikizmet, reporting, chaseiq)
- `ManagedBy` (terraform, manual)
- `Owner` (team name or service)

Cost allocation tags enabled for billing breakdown.

## Compliance & Auditing

- CloudTrail: Organization trail capturing all API calls across accounts
- Config: Compliance rules for encryption, public access, tagging
- GuardDuty: Threat detection across all accounts
- AWS Security Hub: Centralized security findings
- Quarterly reviews: `/aws-architecture-review`, `/aws-credentials-audit`

## Support & Escalation

- **AWS Support:** Business plan (response time: <1 hour for urgent, <12h for normal)
- **On-call:** PagerDuty integration with CloudWatch alarms
- **Runbooks:** Stored in `docs/runbooks/` of each infrastructure repo
- **Slack:** `#cloud-infra-team` for questions, `#aws-alerts` for alarms
