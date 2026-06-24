---
name: aws-reserved-capacity
description: Review Reserved Instances and Savings Plans utilization, coverage, and expiration. Use for quarterly RI optimization reviews or when evaluating commitment purchases.
---

## AWS Reserved Capacity Review

Analyze Reserved Instance (RI) and Savings Plans utilization to maximize cost savings and identify optimization opportunities.

### Prerequisites

- AWS CLI with Cost Explorer and EC2/RDS describe permissions
- `jq` for JSON parsing

### Workflow

1. **List active RDS Reserved Instances with utilization**
   ```bash
   aws rds describe-reserved-db-instances --region us-west-2 | jq -r '.ReservedDBInstances[] | select(.State == "active") | "\(.ReservedDBInstanceId): \(.DBInstanceClass) x\(.DBInstanceCount) - Expires: \(.StartTime | fromdateiso8601 + .Duration | todateiso8601 | split("T")[0])"'
   ```

2. **Check RDS RI utilization (last 30 days)**
   ```bash
   aws ce get-reservation-utilization --region us-west-2 --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --filter file:///dev/stdin <<< '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}' | jq -r '.UtilizationsByTime[] | "\(.TimePeriod.Start): \(.Total.UtilizationPercentage)% utilized"'
   ```

3. **Find RIs expiring in next 90 days**
   ```bash
   NINETY_DAYS=$(date -u -d '90 days' +%s)
   aws rds describe-reserved-db-instances --region us-west-2 | jq -r --arg expiry "$NINETY_DAYS" '.ReservedDBInstances[] | select(.State == "active") | select((.StartTime | fromdateiso8601) + .Duration < ($expiry | tonumber)) | "\(.DBInstanceClass) x\(.DBInstanceCount) expires \(.StartTime | fromdateiso8601 + .Duration | todateiso8601 | split("T")[0])"'
   ```

4. **Calculate On-Demand RDS instances (RI coverage gap)**
   ```bash
   aws rds describe-db-instances --region us-west-2 | jq -r '.DBInstances[] | select(.Engine | startswith("aurora")) | "\(.DBInstanceIdentifier): \(.DBInstanceClass)"' > /tmp/rds-instances.txt
   
   # Compare against RIs to find uncovered instances
   # Flag instances running >50% of month that could benefit from RIs
   ```

5. **Check ECS Fargate Savings Plans coverage**
   ```bash
   aws ce get-savings-plans-coverage --region us-west-2 --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) --granularity MONTHLY | jq -r '.SavingsPlansCoverages[] | "Coverage: \(.Coverage.CoveragePercentage)% | On-Demand Cost: $\(.Coverage.OnDemandCost) | Savings Plans Cost: $\(.Coverage.SpendCoveredBySavingsPlans)"'
   ```

6. **Estimate savings from unconverted On-Demand (RDS example)**
   - For each uncovered instance, calculate:
     - Monthly On-Demand cost: `hours * instance_rate`
     - 1-year All Upfront RI cost: `upfront + (hours * hourly_rate)`
     - Savings: `(On-Demand - RI) / On-Demand * 100`
   
   ```bash
   # Example for db.r6g.2xlarge (common iKizmet size)
   ON_DEMAND_HOURLY=1.016  # us-west-2 pricing
   RI_UPFRONT_1YR=5447
   RI_HOURLY_1YR=0.000
   HOURS_PER_MONTH=730
   
   echo "On-Demand monthly: $(echo "$ON_DEMAND_HOURLY * $HOURS_PER_MONTH" | bc -l)"
   echo "1yr RI monthly (amortized): $(echo "($RI_UPFRONT_1YR / 12) + ($RI_HOURLY_1YR * $HOURS_PER_MONTH)" | bc -l)"
   echo "Savings: $(echo "(1 - (($RI_UPFRONT_1YR / 12) / ($ON_DEMAND_HOURLY * $HOURS_PER_MONTH))) * 100" | bc -l)%"
   ```

7. **Generate recommendations report**
   - List underutilized RIs (<70% avg utilization) — consider modifying or selling
   - List expiring RIs (next 90 days) — renew or convert to On-Demand
   - Calculate ROI for converting On-Demand to RI (break-even month)
   - Recommend Savings Plans for Fargate if coverage <80%

### Output Format

```
=== AWS Reserved Capacity Review: June 2026 ===

RDS Reserved Instances (5 active):
✅ db.r6g.2xlarge x2 — 94% utilized, expires 2027-03-15
✅ db.r6g.xlarge x4 — 88% utilized, expires 2027-01-20
⚠️  db.r5.large x2 — 62% utilized, expires 2026-09-10 (underutilized)
🔴 db.t4g.medium x1 — 15% utilized, expires 2026-08-05 (waste)

Expiring Soon (next 90 days):
- db.r5.large x2 — expires 2026-09-10 ($X/month saved, renew recommended)
- db.t4g.medium x1 — expires 2026-08-05 (underutilized, do NOT renew)

On-Demand RDS Instances (RI candidates):
1. app-prod-writer (db.r6g.4xlarge) — running 24/7
   - Current cost: $1,483/month On-Demand
   - 1yr RI cost: $907/month (39% savings)
   - 3yr RI cost: $621/month (58% savings)
   - Recommendation: Purchase 1yr All Upfront RI

2. app-qa-cluster (db.r6g.large) — running business hours only
   - Current cost: $185/month On-Demand
   - RI break-even: 9.2 months (not recommended, <80% utilization)

ECS Fargate Savings Plans:
- Current coverage: 65%
- On-Demand spend (uncovered): $2,100/month
- Potential 1yr Compute SP savings: ~$630/month (30% discount)
- Recommendation: Purchase $1,500/month 1yr Compute Savings Plan

Total Monthly Savings Potential: $1,537/month ($18,444/year)
```

### Integration

- Run after `/aws-cost-review` identifies high RDS or ECS costs
- Before purchasing RIs, run `/aws-rds-rightsizing` to ensure correct instance sizing

### Notes

- RI purchases require `rds:PurchaseReservedDBInstancesOffering` permission
- All Upfront RIs have lowest cost but require CFO approval for large spend
- Convertible RIs cost ~5% more but allow instance class changes
- Savings Plans are more flexible than RIs but have same commitment risk
