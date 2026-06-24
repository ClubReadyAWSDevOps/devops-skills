---
name: aws-cost-review
description: Monthly AWS budget analysis, spend trends, anomaly detection, and cost driver identification. Use when reviewing AWS costs, budget compliance, or investigating spend increases.
---

## AWS Cost Review

Comprehensive monthly cost analysis across all AWS services with trend comparison and anomaly detection.

### Prerequisites

- AWS CLI configured with Cost Explorer API access
- `jq` installed for JSON parsing

### Workflow

1. **Fetch current month-to-date spend by service**
   ```bash
   aws ce get-cost-and-usage --region us-west-2 --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE | jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0]): $\(.Metrics.BlendedCost.Amount | tonumber | round)"' | sort -t'$' -k2 -rn
   ```

2. **Compare vs last month (full month)**
   ```bash
   LAST_MONTH_START=$(date -u -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01)
   LAST_MONTH_END=$(date -u -d "$(date +%Y-%m-01) -1 day" +%Y-%m-%d)
   aws ce get-cost-and-usage --region us-west-2 --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END --granularity MONTHLY --metrics BlendedCost | jq -r '.ResultsByTime[0].Total.BlendedCost.Amount'
   ```

3. **Identify top 10 cost drivers (resource-level)**
   ```bash
   aws ce get-cost-and-usage --region us-west-2 --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=LINKED_ACCOUNT --group-by Type=DIMENSION,Key=SERVICE | jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0]) - \(.Keys[1]): $\(.Metrics.BlendedCost.Amount | tonumber | round)"' | sort -t'$' -k2 -rn | head -10
   ```

4. **Flag daily anomalies (>20% increase day-over-day)**
   ```bash
   aws ce get-cost-and-usage --region us-west-2 --time-period Start=$(date -u -d '14 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity DAILY --metrics BlendedCost | jq -r '.ResultsByTime[] | "\(.TimePeriod.Start): $\(.Total.BlendedCost.Amount | tonumber | round)"'
   ```
   
   Calculate day-over-day % change and flag >20% increases. If found, drill into service-level for that day:
   ```bash
   aws ce get-cost-and-usage --region us-west-2 --time-period Start=YYYY-MM-DD,End=YYYY-MM-DD --granularity DAILY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE
   ```

5. **Check budget compliance (if Cost Explorer budgets configured)**
   ```bash
   aws budgets describe-budgets --region us-west-2 --account-id $(aws sts get-caller-identity --query Account --output text) | jq -r '.Budgets[] | "\(.BudgetName): \(.CalculatedSpend.ActualSpend.Amount)/\(.BudgetLimit.Amount) (\((.CalculatedSpend.ActualSpend.Amount | tonumber) / (.BudgetLimit.Amount | tonumber) * 100 | round))%"'
   ```

6. **Generate summary report**
   - Current month spend vs last month ($ and %)
   - Top 5 services by cost
   - Any anomalies detected (>20% daily increases)
   - Budget status (on track / over / under)
   - Action items (e.g., "Investigate RDS spike on 2026-06-15")

### Output Format

```
=== AWS Cost Review: June 2026 ===

Current Month (MTD): $45,230
Last Month (Full):   $52,100 (-13%)
Projected End-Month: $60,300 (+16% vs last month)

Top 5 Services:
1. RDS:                    $18,500 (41%)
2. EC2:                    $12,200 (27%)
3. S3:                     $6,800 (15%)
4. DynamoDB:               $3,200 (7%)
5. Data Transfer:          $2,100 (5%)

Anomalies Detected:
- 2026-06-15: +32% spike ($1,850 → $2,442) — RDS increased $500
- 2026-06-20: +24% spike ($2,100 → $2,604) — EC2 increased $400

Budget Status:
✅ Production: $45k / $60k (75%, on track)
⚠️  Development: $12k / $10k (120%, over budget)

Action Items:
1. Investigate RDS spike on 2026-06-15 (new instance launched?)
2. Review Development EC2 usage (over budget by 20%)
3. Check for orphaned EBS volumes (common cost driver)
```

### Integration with Other Skills

After identifying high-cost resources:
- **RDS high cost** → run `/aws-rds-rightsizing` to check for over-provisioned instances
- **Snapshot cost high** → run `/aws-snapshot-cleanup` to find orphaned snapshots
- **Low RI utilization** → run `/aws-reserved-capacity` to review Reserved Instance coverage

### Notes

- Cost Explorer data has a 24-hour lag — "today" reflects yesterday's spend
- Use `--granularity HOURLY` for recent anomaly deep-dives (last 14 days only)
- Tag-based cost allocation requires tags to be activated in Cost Allocation Tags settings
