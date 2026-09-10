# PIQ Development Aurora Findings

Review date: 2026-09-10. All database inspection used TLS, existing Secrets Manager credentials, and read-only transactions unless an explicitly confirmed change is recorded below. No secret values or application payloads were stored.

## Executive summary

The PIQ development cluster is effectively a full production-sized copy. Before cleanup, it used approximately 10.23 TiB of Aurora storage. Five unpartitioned tables represented about 93% of logical table and index storage. The largest table, `piqapp.api_logs`, was 4.48 TiB and was truncated on development after explicit confirmation.

Aurora I/O-Optimized is not economical for PIQ at the current storage size. The more valuable actions are reducing the development dataset, controlling production data growth, reviewing backup overlap, and fixing the August production read-I/O surge.

## Cost history

Unblended account spend:

| Month | PIQ account spend |
|---|---:|
| 2026-06 | $13,877.65 |
| 2026-07 | $12,387.10 |
| 2026-08 | $9,132.08 |

August RDS drivers:

| Usage | Cost |
|---|---:|
| Aurora Standard storage | $1,802.85 |
| Aurora Standard I/O | $1,300.87 |
| `db.r8g.2xlarge` instances | $768.77 |
| Aurora backup storage, us-west-2 | $260.63 |
| RDS Proxy | $199.83 |
| Aurora backup storage, EU | $13.04 |

## Current topology

| Cluster | Purpose | Instances | Storage mode | Storage observed | Backup retention |
|---|---|---|---|---:|---:|
| `piqmaster-cluster-1` | Production | 2 × `db.r8g.2xlarge` | Aurora Standard | 10.25 TiB | 30 days |
| `piqdev-cluster1-2026-08-24` | Development | 1 × `db.t3.medium` | Aurora Standard | 10.23 TiB before cleanup | 1 day |

The development cluster was restored with approximately the same data volume as production rather than with a reduced dataset.

## Standard versus I/O-Optimized

PIQ should remain on Aurora Standard.

August production model using AWS Pricing API rates:

| Component | Modeled monthly effect of I/O-Optimized |
|---|---:|
| Avoided production I/O charge | -$1,445.65 |
| Added storage premium | +$1,276.19 |
| Added instance premium | +$512.80 |
| **Net** | **+$343.34 more expensive** |

With the common 11% effective discount observed in billing applied equally, I/O-Optimized was still approximately $306 more expensive. Current break-even is approximately 8.85 billion production I/O requests per month; August production generated about 7.23 billion.

Do not apply the generic “I/O is a large percentage of spend” heuristic without including PIQ's 10+ TiB storage premium.

## August read-I/O anomaly

| Metric | July 2026 | August 2026 | Change |
|---|---:|---:|---:|
| Account I/O requests | 3.35B | 7.31B | +118.5% |
| Production reads | 408M | 4.62B | about +1,033% |
| Production writes | 2.80B | 2.61B | about -7% |

The increase began around 2026-08-02 and was read-driven. Production also appears to have moved from two `r8g.4xlarge` instances to two `r8g.2xlarge` instances around the same time. Reduced buffer cache is a plausible contributor, but query-level causality was not proven.

Follow-up metrics and evidence:

- Compare `BufferCacheHitRatio` before and after 2026-08-02.
- Review Performance Insights for high-read SQL and load changes.
- Review application releases, reports, ETL jobs, and query-plan changes from 2026-08-01 through 2026-08-03.
- Compare compute savings from the instance reduction with the additional I/O cost.

## Development logical storage before `api_logs` truncation

| Schema | Data | Indexes | Total |
|---|---:|---:|---:|
| `piqapp` | 6,287.28 GiB | 1,413.71 GiB | 7,700.99 GiB |
| `piqapp_emails` | 1,049.08 GiB | 10.60 GiB | 1,059.68 GiB |
| **Logical total** | | | **8,760.67 GiB** |

Aurora `VolumeBytesUsed` was approximately 10,231 GiB. The difference includes Aurora internal storage, undo/history, and allocation that is not represented as active logical table/index bytes.

## Largest development tables before cleanup

| Table | Estimated rows | Data | Index | Total | Last observed write |
|---|---:|---:|---:|---:|---|
| `piqapp.api_logs` | 4.35B | 4,250.70 GiB | 233.19 GiB | 4,483.89 GiB | 2026-09-04 |
| `piqapp.power_series` | 22.37B | 932.30 GiB | 470.66 GiB | 1,402.96 GiB | linked parent: 2026-08-24 |
| `piqapp_emails.emails` | 50.97M | 1,049.03 GiB | 10.53 GiB | 1,059.56 GiB | 2026-08-31 |
| `piqapp.hr_series` | 16.55B | 633.52 GiB | 352.25 GiB | 985.77 GiB | not rechecked after inventory |
| `piqapp.rower_series` | 3.58B | 151.15 GiB | 75.73 GiB | 226.88 GiB | not rechecked after inventory |
| `piqapp.booking_reservations` | 191.12M | 45.12 GiB | 89.45 GiB | 134.57 GiB | 2026-08-27 metadata |
| `piqapp.clubready_reservation_log` | 809.75M | 90.06 GiB | 31.91 GiB | 121.97 GiB | 2026-09-04 |
| `piqapp.clubready_reservations` | 181.21M | 26.52 GiB | 67.52 GiB | 94.04 GiB | 2026-09-04 |
| `piqapp.class_sync_logs` | 1.32B | 89.54 GiB | 0 | 89.54 GiB | 2026-09-04 |

The top five represented approximately 93% of logical table and index storage. None of the large tables was partitioned.

## `api_logs` findings and completed change

Structure:

- Primary key: `id`
- Secondary index: `client_id`
- Timestamp representation: unindexed integer column `time`
- Large payload contributor: `params` text column
- History observed: 2018-07-26 through 2026-09-04

Approximate ID-age samples showed that 80% of the ID range predated February 2025 and 90% predated October 2025.

Live check on 2026-09-10:

- Latest ID: `5110697735`
- Latest timestamp: `2026-09-04 14:55:45`
- ID change during a 15-second check: zero
- No referencing foreign keys or triggers

Completed operation on 2026-09-10:

```sql
TRUNCATE TABLE piqapp.api_logs;
```

Post-change verification:

- Exact row count: zero
- Data allocation: 0.016 MiB
- Index allocation: 0.016 MiB
- `AUTO_INCREMENT`: 1
- Execution time: 5.67 seconds

Aurora physical and billing reclamation is asynchronous. The expected eventual active-storage reduction is approximately 4.48 TiB, worth roughly $400/month. Backups can retain old pages until recovery points expire.

## `power_series` findings

Structure:

| Column | Type | Indexed |
|---|---|---|
| `stats_id` | `bigint unsigned` | Yes, non-unique |
| `class_time` | `smallint unsigned` | No |
| `rpm` | `tinyint unsigned` | No |
| `power` | `smallint unsigned` | No |

There is no primary key, foreign-key constraint, or partitioning. `stats_id` relates logically to `power_stats.id`.

Activity check:

- Stats ID range: 0 through 56,935,876
- Oldest linked timestamp: 2017-07-22
- Newest linked timestamp: 2026-08-24 02:01:11
- Latest group: 525 samples
- Maximum stats ID and latest-group row count did not change during a 15-second check

Conclusion: the development table was not receiving writes at review time. It remains unchanged.

### Date-retention mapping

`power_series` has no date. A cutoff must be derived from indexed `power_stats.timestamp` and applied through indexed `power_series.stats_id`.

| Keep from | Approximate first stats ID | Estimated older rows | Estimated removable storage |
|---|---:|---:|---:|
| 2022-01-01 | 25,640,999 | 45.0% | 631.8 GiB |
| 2023-01-01 | 32,477,366 | 57.0% | 800.3 GiB |
| 2024-01-01 | 40,095,826 | 70.4% | 988.0 GiB |
| 2025-01-01 | 47,408,438 | 83.3% | 1,168.2 GiB |
| 2026-01-01 | 53,436,298 | 93.9% | 1,316.7 GiB |

These are proportional estimates, not exact counts. Query plans confirmed range access on both indexes.

Do not delete tens of billions of rows in place. For a recent-only development dataset, create a replacement table containing the retained `stats_id` range, validate it, atomically rename tables, and drop the old table only after explicit approval.

## Email storage

`piqapp_emails.emails` stores large bodies in `longtext` and `mediumtext` columns, including HTML, plain-text content, calendar data, and error text. History runs from 2020-01-04 through 2026-08-31. Development should not retain full historical email bodies unless a specific test requires them.

## Backup findings

- Production uses native Aurora automated backups with 30-day retention.
- AWS Backup also creates daily recovery points with 30-day retention.
- Validate whether both mechanisms are required for compliance, vault isolation, or restore semantics.
- A July 2026 snapshot deletion batch reduced backup cost by approximately $985/month.
- The final snapshot for the previous development cluster is about 10,005 GiB and adds an estimated $187/month.
- A 2017 manual snapshot in `eu-west-1` is about 697 GiB and costs approximately $13/month.

Snapshot sizes are logical; Aurora snapshots are incremental and must not be summed to estimate physical billing.

## Production storage growth

Production storage grew from approximately 5.13 TiB to 10.25 TiB over one year, an increase of about 5.0 TiB. At the effective storage rate, that growth represents roughly $448/month.

Investigate retention and archival for API logs, telemetry series, email bodies, reservation logs, sync logs, and obsolete tenant data.

## Prioritized opportunities

| Priority | Action | Approximate monthly effect |
|---|---|---:|
| Completed | Truncate development `api_logs` | about $400 after reclamation |
| P1 | Replace full dev copy with schema-only or curated reduced dataset | up to about $820 |
| P2 | Review/delete previous 10 TiB dev final snapshot | about $187 |
| P3 | Investigate August production read-I/O surge | up to about $700 excess I/O |
| P4 | Retain only required development telemetry/email history | about $120–300 depending on policy |
| P5 | Review native Aurora plus AWS Backup overlap | measure after policy decision |
| P6 | Review 2017 EU snapshot | about $13 |

## Constraints and exclusions

- Reserved Instances and Savings Plans are managed by a third party and are out of scope.
- MySQL has no PostgreSQL-style `VACUUM` or dead-tuple metric.
- `TRUNCATE` and `DROP` release table allocation; Aurora storage and backup billing metrics update asynchronously.
- Large in-place `DELETE` plus `OPTIMIZE TABLE` operations are inappropriate for multi-terabyte tables without a separate tested migration plan.
