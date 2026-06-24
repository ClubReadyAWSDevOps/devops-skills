---
name: aws-architecture-review
description: Comprehensive AWS architecture review covering HA, security, cost efficiency, and Well-Architected Framework pillars. Use for quarterly reviews, pre-launch audits, or cost optimization initiatives.
---

## AWS Architecture Review

Multi-dimensional architecture audit aligned with AWS Well-Architected Framework: Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, and Sustainability.

### Prerequisites

- AWS CLI with read access across all services
- `jq` for JSON parsing
- Terraform state access (if infrastructure-as-code)

### Review Dimensions

## 1. High Availability & Resilience

**1.1 Multi-AZ Coverage**
```bash
# RDS clusters
aws rds describe-db-clusters --region us-west-2 | jq -r '.DBClusters[] | select(.MultiAZ == false) | "⚠️  \(.DBClusterIdentifier): Single-AZ cluster (not HA)"'

# ECS services
aws ecs list-services --region us-west-2 --cluster <cluster-name> --query 'serviceArns[*]' --output text | while read arn; do
  SERVICE=$(basename "$arn")
  DESIRED=$(aws ecs describe-services --region us-west-2 --cluster <cluster-name> --services "$SERVICE" --query 'services[0].desiredCount' --output text)
  if [ "$DESIRED" -lt 2 ]; then
    echo "⚠️  $SERVICE: Desired count < 2 (no redundancy)"
  fi
done

# ALB target groups
aws elbv2 describe-target-health --region us-west-2 --target-group-arn <arn> | jq -r 'group_by(.TargetHealth.State) | map({state: .[0].TargetHealth.State, count: length}) | .[]'
```

**1.2 Backup & Recovery**
```bash
# RDS automated backups
aws rds describe-db-clusters --region us-west-2 | jq -r '.DBClusters[] | select(.BackupRetentionPeriod < 7) | "⚠️  \(.DBClusterIdentifier): Backup retention \(.BackupRetentionPeriod) days (recommend 7+)"'

# RDS snapshots (manual backup existence)
aws rds describe-db-cluster-snapshots --region us-west-2 --snapshot-type manual | jq -r '.DBClusterSnapshots | group_by(.DBClusterIdentifier) | map({cluster: .[0].DBClusterIdentifier, count: length, latest: (.[0].SnapshotCreateTime // "never")}) | .[]'

# S3 versioning enabled
aws s3api list-buckets --region us-west-2 --query 'Buckets[*].Name' --output text | while read bucket; do
  VERSIONING=$(aws s3api get-bucket-versioning --bucket "$bucket" 2>/dev/null | jq -r '.Status // "Disabled"')
  if [ "$VERSIONING" != "Enabled" ]; then
    echo "❌ $bucket: Versioning disabled (data loss risk)"
  fi
done
```

**1.3 Disaster Recovery Plan**
- Document RTO (Recovery Time Objective) and RPO (Recovery Point Objective)
- Test failover procedures quarterly
- Check cross-region replication for critical data

## 2. Security Posture

**2.1 Network Isolation**
```bash
# Public RDS instances (CRITICAL)
aws rds describe-db-instances --region us-west-2 | jq -r '.DBInstances[] | select(.PubliclyAccessible == true) | "🔴 \(.DBInstanceIdentifier): PUBLICLY ACCESSIBLE — immediate fix required"'

# Security groups with 0.0.0.0/0 ingress
aws ec2 describe-security-groups --region us-west-2 | jq -r '.SecurityGroups[] | select(.IpPermissions[] | .IpRanges[] | .CidrIp == "0.0.0.0/0") | "⚠️  \(.GroupName) (\(.GroupId)): Open to internet on port \(.IpPermissions[].FromPort)"'

# S3 buckets with public access
aws s3api list-buckets --region us-west-2 --query 'Buckets[*].Name' --output text | while read bucket; do
  PUBLIC_BLOCK=$(aws s3api get-public-access-block --bucket "$bucket" 2>/dev/null | jq -r '.PublicAccessBlockConfiguration | if .BlockPublicAcls == true and .BlockPublicPolicy == true then "blocked" else "open" end')
  if [ "$PUBLIC_BLOCK" = "open" ]; then
    echo "🔴 $bucket: Public access not fully blocked"
  fi
done
```

**2.2 Encryption**
```bash
# RDS encryption at rest
aws rds describe-db-clusters --region us-west-2 | jq -r '.DBClusters[] | select(.StorageEncrypted == false) | "❌ \(.DBClusterIdentifier): Encryption disabled"'

# S3 default encryption
aws s3api list-buckets --region us-west-2 --query 'Buckets[*].Name' --output text | while read bucket; do
  ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$bucket" 2>&1)
  if echo "$ENCRYPTION" | grep -q "ServerSideEncryptionConfigurationNotFoundError"; then
    echo "❌ $bucket: No default encryption"
  fi
done

# EBS volumes unencrypted
aws ec2 describe-volumes --region us-west-2 | jq -r '.Volumes[] | select(.Encrypted == false) | "⚠️  \(.VolumeId): Unencrypted EBS volume (attached to \(.Attachments[0].InstanceId // "none"))"'
```

**2.3 Secrets Management**
```bash
# Hardcoded secrets in Lambda env vars (pattern detection)
aws lambda list-functions --region us-west-2 --query 'Functions[*].FunctionName' --output text | while read fn; do
  aws lambda get-function-configuration --region us-west-2 --function-name "$fn" | jq -r '.Environment.Variables | to_entries[] | select(.key | test("PASSWORD|SECRET|KEY|TOKEN"; "i")) | "⚠️  \(env.fn): Env var \(.key) may contain secret (use Secrets Manager)"'
done
```

## 3. Cost Optimization

**3.1 Over-Provisioned Resources**
```bash
# RDS instances with low CPU (<20% avg last 14 days)
aws cloudwatch get-metric-statistics --region us-west-2 --namespace AWS/RDS --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=<instance-id> --start-time $(date -u -d '14 days ago' --iso-8601=seconds) --end-time $(date -u --iso-8601=seconds) --period 86400 --statistics Average | jq -r '.Datapoints | add / length | if . < 20 then "⚠️  <instance-id>: Avg CPU \(.)% — consider downsizing" else empty end'

# ECS tasks with low memory utilization
# (requires Container Insights enabled)
aws cloudwatch get-metric-statistics --region us-west-2 --namespace ECS/ContainerInsights --metric-name MemoryUtilized --dimensions Name=ServiceName,Value=<service> Name=ClusterName,Value=<cluster> --start-time $(date -u -d '7 days ago' --iso-8601=seconds) --end-time $(date -u --iso-8601=seconds) --period 86400 --statistics Average
```

**3.2 Idle Resources**
```bash
# Stopped EC2 instances still incurring EBS costs
aws ec2 describe-instances --region us-west-2 --filters "Name=instance-state-name,Values=stopped" | jq -r '.Reservations[].Instances[] | "💰 \(.InstanceId): Stopped since \(.StateTransitionReason) — EBS volumes still costing"'

# Unattached EBS volumes
aws ec2 describe-volumes --region us-west-2 --filters "Name=status,Values=available" | jq -r '.Volumes[] | "💰 \(.VolumeId): \(.Size)GB unattached since \(.CreateTime) — $\(.Size * 0.10)/month waste"'

# Old EBS snapshots (>90 days, no active AMI)
aws ec2 describe-snapshots --region us-west-2 --owner-ids self | jq -r --arg cutoff "$(date -u -d '90 days ago' --iso-8601)" '.Snapshots[] | select(.StartTime < $cutoff) | "\(.SnapshotId): \(.VolumeSize)GB from \(.StartTime)"'
```

**3.3 Graviton Adoption (cost & performance)**
```bash
# x86 instances where ARM64 equivalent exists
aws ec2 describe-instances --region us-west-2 --filters "Name=instance-state-name,Values=running" | jq -r '.Reservations[].Instances[] | select(.InstanceType | startswith("m5") or startswith("r5") or startswith("t3")) | "💡 \(.InstanceId) (\(.InstanceType)): Graviton equivalent (m7g/r7g/t4g) available (20-40% cheaper)"'

# RDS instances not using Graviton
aws rds describe-db-instances --region us-west-2 | jq -r '.DBInstances[] | select(.DBInstanceClass | contains("r5") or contains("r6i")) | "💡 \(.DBInstanceIdentifier) (\(.DBInstanceClass)): Graviton (r6g/r7g) available (10-30% cheaper)"'
```

## 4. Performance & Scalability

**4.1 Auto-Scaling Configuration**
```bash
# ECS services without auto-scaling
aws ecs list-services --region us-west-2 --cluster <cluster> --query 'serviceArns[*]' --output text | while read arn; do
  SERVICE=$(basename "$arn")
  SCALING=$(aws application-autoscaling describe-scalable-targets --region us-west-2 --service-namespace ecs --resource-ids "service/<cluster>/$SERVICE" --query 'length(ScalableTargets)' --output text)
  if [ "$SCALING" -eq 0 ]; then
    echo "⚠️  $SERVICE: No auto-scaling configured"
  fi
done

# RDS Aurora without auto-scaling replicas
aws rds describe-db-clusters --region us-west-2 | jq -r '.DBClusters[] | select(.Engine | startswith("aurora")) | select(.ScalingConfigurationInfo == null) | "⚠️  \(.DBClusterIdentifier): No Aurora Serverless or auto-scaling readers"'
```

**4.2 Caching Strategy**
```bash
# CloudFront distributions (CDN)
aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,Origins.Items[0].DomainName,Enabled]' --output table

# ElastiCache clusters
aws elasticache describe-cache-clusters --region us-west-2 | jq -r '.CacheClusters[] | "\(.CacheClusterId): \(.Engine) \(.CacheNodeType) x\(.NumCacheNodes)"'

# Check for direct DB queries that should be cached
# (requires application-level review)
```

## 5. Observability & Operations

**5.1 Logging**
```bash
# RDS query logs enabled
aws rds describe-db-clusters --region us-west-2 | jq -r '.DBClusters[] | select(.EnabledCloudwatchLogsExports == null or (.EnabledCloudwatchLogsExports | length == 0)) | "⚠️  \(.DBClusterIdentifier): CloudWatch Logs not enabled"'

# VPC Flow Logs
aws ec2 describe-flow-logs --region us-west-2 --query 'length(FlowLogs)' --output text
# If 0, VPC flow logs not enabled (network visibility gap)

# S3 access logging
aws s3api list-buckets --region us-west-2 --query 'Buckets[*].Name' --output text | while read bucket; do
  LOGGING=$(aws s3api get-bucket-logging --bucket "$bucket" 2>/dev/null | jq -r '.LoggingEnabled // empty')
  if [ -z "$LOGGING" ]; then
    echo "⚠️  $bucket: Access logging disabled"
  fi
done
```

**5.2 Monitoring & Alerts**
```bash
# Critical metrics without CloudWatch alarms
# List expected alarms: RDS CPU, ECS CPU/Memory, ALB 5xx, Lambda errors
aws cloudwatch describe-alarms --region us-west-2 | jq -r '.MetricAlarms[] | "\(.AlarmName): \(.MetricName) on \(.Namespace)"'

# Check for missing alarms on critical resources
# (requires defining "critical" in your context)
```

## 6. Infrastructure-as-Code Coverage

```bash
# Compare AWS resources vs Terraform state
cd /path/to/terraform
terraform state list > /tmp/tf-managed.txt

# Find resources NOT in Terraform (manual drift)
aws ec2 describe-instances --region us-west-2 --query 'Reservations[].Instances[].InstanceId' --output text | while read id; do
  if ! grep -q "$id" /tmp/tf-managed.txt; then
    echo "❌ $id: EC2 instance not managed by Terraform"
  fi
done

# Repeat for RDS, S3, ALBs, etc.
```

### Output Format

Generate a scored report card across 6 dimensions:

```
=== AWS Architecture Review: Production Account (2026-06-24) ===

1. HIGH AVAILABILITY & RESILIENCE: B+ (85/100)
   ✅ All RDS clusters are Multi-AZ
   ✅ ECS services have 2+ tasks
   ⚠️  3 services lack cross-AZ placement
   ⚠️  Manual snapshot backups <30 days old (stale)

2. SECURITY POSTURE: C (72/100)
   🔴 1 RDS instance publicly accessible (CRITICAL)
   ✅ All RDS clusters encrypted at rest
   ⚠️  5 security groups open to 0.0.0.0/0
   ⚠️  3 S3 buckets without default encryption
   ✅ Root MFA enabled
   
3. COST OPTIMIZATION: B- (78/100)
   💰 $1,200/month waste from 12 unattached EBS volumes
   💰 $800/month savings potential from Graviton migration
   ⚠️  2 RDS instances <20% CPU (over-provisioned)
   ✅ 85% RI coverage on production RDS

4. PERFORMANCE & SCALABILITY: A- (88/100)
   ✅ All ECS services have auto-scaling
   ✅ CloudFront CDN in use
   ⚠️  No ElastiCache (database caching layer missing)
   ✅ Aurora read replicas auto-scale

5. OBSERVABILITY: B (82/100)
   ⚠️  VPC Flow Logs not enabled
   ⚠️  3 RDS clusters without query logging
   ✅ All critical metrics have CloudWatch alarms
   ⚠️  5 S3 buckets without access logging

6. INFRASTRUCTURE-AS-CODE: C+ (75/100)
   ⚠️  18 resources not in Terraform (manual drift)
   ⚠️  Terraform state not using remote backend locking
   ✅ Core infrastructure (RDS, ECS) fully managed

OVERALL SCORE: B (80/100)

=== Top 5 Action Items ===
1. 🔴 Remove public access from app-legacy-db RDS instance (security)
2. 💰 Delete 12 unattached EBS volumes ($1,200/month savings)
3. ⚠️  Enable VPC Flow Logs (security/compliance)
4. 💰 Migrate 3 m5 instances to m7g Graviton ($800/month savings)
5. ⚠️  Import 18 manually-created resources into Terraform
```

### Integration

- Run **quarterly** for continuous architecture improvement
- Run **before major launches** to validate production-readiness
- Integrate with `/aws-cost-review` for detailed cost breakdowns
- Combine with `/aws-credentials-audit` for full security posture

### Notes

- This review focuses on AWS-native services (RDS, ECS, S3, etc.)
- Application-level architecture (microservices, data flow) requires separate review
- Well-Architected Tool in AWS Console provides additional guided review
- Consider AWS Trusted Advisor for automated best-practice checks (requires Business+ support)
