# Frankfurt QA Storage-Mode Reevaluation

Review date: 2026-09-10  
AWS linked account: `410878187014` (`sa-ikizmet`)  
Payer account: `381492115765` (`sa-cr`)  
Region: `eu-central-1`  
Cluster: `app-qa-cluster`  
Status: read-only analysis; no configuration change made

## Validated recommendation

Aurora I/O-Optimized is economically favorable for the Frankfurt QA global secondary, but only by a small amount:

- Complete August workload: approximately **`$11.86/month` public** or **`$10.55/month` net** after the observed 11% enterprise discount.
- September 1–9 run rate: approximately **`$33.90/month` public** or **`$30.17/month` net**, but this period is partial and estimated.
- Practical classification: low-priority `$10–30 net/month` optimization.

The previous estimate of approximately `$121.58/month` was overstated and is withdrawn.

## Why the previous estimate was wrong

Two attribution assumptions were incorrect:

1. Account-level Frankfurt usage included many temporary `qa-pr-*` Aurora clusters. Their Serverless ACU and ordinary storage I/O cannot be attributed to `app-qa-cluster`.
2. Global replicated-write I/O remains separately billed under both Standard and I/O-Optimized. It does not disappear under I/O-Optimized and must cancel out of the storage-mode comparison.

Resource-level Cost Explorer is available only for a recent window, but August target CloudWatch quantities were validated against target resource billing during the overlapping August 27–September 9 period.

## Current topology

- Aurora PostgreSQL 17.9
- Global database: `app-qa`
- Oregon `app-qa`: writer/primary
- Frankfurt `app-qa-cluster`: connected, non-writer secondary
- One `db.serverless` instance in `eu-central-1a`
- Serverless v2 range: 0.5–8 ACU
- Current storage mode: Standard (`StorageType=null`)
- Write forwarding: disabled
- Native backup retention: seven days

## Storage-mode history

CloudTrail establishes the exact history:

1. 2026-06-29 17:49:47Z: cluster created with `storageType=aurora-iopt1` and Serverless v2 0.5–32 ACU.
2. 2026-06-29 and June 30: scaling changes occurred; storage remained I/O-Optimized.
3. 2026-08-04 17:40:10Z: an SSO AWS CLI `ModifyDBCluster` requested `storageType=aurora`.
4. 2026-08-04 17:41:10–17:41:59Z: Terraform converged the cluster to Standard and 0.5–8 ACU.
5. No later storage-mode change was found through the review time.

The effective transition was between 17:40 and 17:42 UTC on August 4. The cluster is currently eligible for another storage-mode change, but no change was authorized or performed.

## Frankfurt rates used

| Component | Standard | I/O-Optimized |
|---|---:|---:|
| Serverless v2 | `$0.140/ACU-hour` | `$0.190/ACU-hour` |
| Storage | `$0.119/GB-month` | `$0.268/GB-month` |
| Ordinary storage I/O | `$0.22/million` | Included |
| Global replicated writes | `$0.22/million` | `$0.22/million` |

Cost Explorer shows an effective 11% Enterprise Discount Program reduction for these on-demand usage types. There is no provisioned-instance RI involved in Frankfurt Serverless v2.

## Complete August target workload

Target-only quantities:

- Serverless capacity: 636.416 ACU-hours
- Average/mode-weighted storage: approximately 49.982 GB-month
- Ordinary storage I/O: 232.38M requests
- Global replicated-write I/O: 232.341M requests
- Average capacity: approximately 0.855 ACU
- Daily ordinary writes: 5.748M–11.065M
- Configured-capacity peaks repeatedly reached 8 ACU

The first 3.74 days were I/O-Optimized; the remainder was Standard. August target ordinary I/O is almost entirely writes replicated from Oregon. Reads were negligible.

## Corrected counterfactual

Replicated writes are included in both scenarios because AWS bills them in both modes.

| August scenario | Compute | Storage | Ordinary I/O | Replicated writes | Public total | Net total |
|---|---:|---:|---:|---:|---:|---:|
| All Standard | `$89.10` | `$5.95` | `$51.12` | `$51.11` | **`$197.28`** | **`$175.58`** |
| Actual mixed mode | `$92.95` | `$6.79` | `$45.30` | `$51.11` | **`$196.16`** | **`$174.58`** |
| All I/O-Optimized | `$120.92` | `$13.40` | `$0` | `$51.11` | **`$185.43`** | **`$165.03`** |

Results:

- All I/O-Optimized versus all Standard: `$11.86/month` public or `$10.55/month` net savings.
- All I/O-Optimized versus the actual mixed August: about `$10.73` public savings.
- The actual mixed period saved only about `$1.13` public versus all Standard.

## Break-even

Only ordinary storage I/O belongs in the break-even calculation:

```text
break-even ordinary I/O =
  (ACU compute premium + storage premium) / Standard I/O rate
```

- August break-even: 178.49M ordinary requests/month
- August actual: 232.38M
- Margin above break-even: 30.2%
- Operational threshold: approximately 180M rolling 30-day ordinary I/O requests

If rolling ordinary I/O falls below approximately 180M, Standard becomes cheaper. Replicated-write volume does not affect this threshold because it is charged in both modes.

## September signal

September 1–9 target activity was higher and more volatile:

- Projected ordinary I/O: approximately 316.32M/month
- Projected break-even: approximately 162.21M/month
- Projected I/O-Optimized savings: `$33.90/month` public or `$30.17/month` net
- September 9 alone reached approximately 19.43M writes

September Cost Explorer data is partial and estimated, so August remains the primary decision month.

## Decision guidance

Switching Frankfurt QA to I/O-Optimized is economically positive, but the saving is too small to justify an urgent change or operational risk.

Before an approved change:

1. Confirm the rolling 30-day ordinary-I/O count remains above 180M.
2. Review why the Serverless instance repeatedly reaches the configured 8-ACU maximum.
3. Record the storage-mode cooldown and rollback timing.
4. Validate global-cluster health and replication alarms.
5. Change only through the Terraform source of truth so configuration does not drift.
6. Compare one complete post-change invoice month against the corrected model.

## Evidence boundaries

- August is complete; September 1–9 is partial and estimated.
- Resource-level Cost Explorer history is limited to 14 days, so older target quantities use CloudWatch validated against the overlapping resource-billing window.
- Cost Explorer daily boundaries and CloudWatch UTC intervals may shift a small number of requests between adjacent days; monthly totals agree closely.
- No endpoint, credential, secret value, customer row, AWS configuration, or database data was changed or exposed.
