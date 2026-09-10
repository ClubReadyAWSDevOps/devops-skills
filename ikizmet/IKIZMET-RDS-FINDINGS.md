# iKizmet RDS and Database Findings

Review date: 2026-09-10  
AWS account: `410878187014` (`sa-ikizmet`)  
Primary region: `us-west-2`  
Secondary region: `eu-central-1`

> Baseline note: this document records the read-only research state before the separately authorized AWS Backup selection change later on 2026-09-10. See [AWS-BACKUP-RDS-CHANGE-2026-09-10.md](AWS-BACKUP-RDS-CHANGE-2026-09-10.md) for the executed change, verification, current state, and rollback.

## Review method and safeguards

The review used read-only AWS APIs for identity, RDS inventory, Cost Explorer, CloudWatch, AWS Backup, snapshots, tags, and Secrets Manager metadata. PostgreSQL inspection was limited to system catalogs and size/statistics functions in TLS-protected, read-only transactions with statement and lock timeouts.

Short-lived IAM database tokens enabled catalog inspection of `app`, `app-xpo`, and `app-qa`. A separate context pass used existing runtime credentials for `app` and `app-xpo` only in process memory. No credential value or customer row payload was printed, logged, or committed. No DDL, DML, maintenance command, AWS mutation, or configuration change was performed.

Cost Explorer can lag and revise recent data. August 2026 is the latest complete month; September values are partial and estimated. Public-rate counterfactuals are not invoice forecasts.

## Executive summary

- RDS remains iKizmet's largest cost category: `$20,360.92` in August, or about 46.7% of the account's `$43,586.25` total.
- `app-xpo` dominates database I/O and is correctly on I/O-Optimized. Its August workload was about `85.003B` requests, over four times its `21.000B` break-even point.
- `app` and Oregon QA remain on I/O-Optimized because payer Cost Explorer confirms their provisioned classes were 100% RI-covered in August; switching to Standard would add billable I/O without reducing the fixed commitment.
- The Frankfurt QA secondary slightly favors I/O-Optimized: corrected target-only modeling shows `$11.86/month` public or `$10.55/month` net August savings. Replicated writes remain billed in both modes.
- Backup charges are material: August Aurora backup usage cost `$1,558.82`, with 30-day native retention and 30-day AWS Backup recovery points overlapping on four clusters.
- XPO is approximately `2.0 TiB`. Five partition families represent roughly 77% of its logical database and several are index-heavy.
- `app_dashboard.delayed_jobs` and `worker_logs` consume about `17 GiB`, approximately 89% of that database, and are high-value retention candidates.
- This audit does not support broad downsizing: major instances reached approximately 99–100% CPU, QA has low free-memory headroom, and connections spike sharply.

## Account-level RDS cost history

| Month | RDS unblended cost | Note |
|---|---:|---|
| January 2026 | `$19,614.11` | Complete |
| February 2026 | `$17,838.64` | Complete |
| March 2026 | `$19,709.65` | Complete |
| April 2026 | `$19,594.29` | Complete |
| May 2026 | `$21,337.72` | Complete |
| June 2026 | `$22,085.40` | Complete |
| July 2026 | `$22,373.77` | Complete |
| August 2026 | `$20,360.92` | Complete |
| September 1–10, 2026 | `$15,077.52` | Partial, estimated, includes recurring-charge timing |

August included large recurring commitment charges and enterprise discounts. Those are intentionally not optimized here. First-day recurring charges must not be interpreted as workload spikes.

Selected August usage charges:

| Usage | Cost | Quantity/evidence |
|---|---:|---:|
| Oregon Aurora backup | `$1,558.82` | 83,404 GB-month usage units |
| Oregon charged RDS backup | `$71.12` | Cost Explorer |
| Oregon I/O-Optimized storage | `$494.61` | 2,469.98 GB-month |
| Oregon I/O-Optimized Serverless v2 | `$300.25` | 2,108.50 ACU-hours |
| Oregon Standard Serverless v2 | `$100.66` | Cost Explorer |
| Oregon Standard Aurora I/O | `$8.46` | 47.50M requests |
| Frankfurt Standard Aurora I/O | `$97.47` | 497.83M requests |
| Frankfurt replicated writes | `$45.49` | 232.34M requests |

## Current topology

| Region | Cluster / role | Engine | Storage configuration | Instances | Latest volume | Native retention |
|---|---|---|---|---|---:|---:|
| Oregon | `app` — production | Aurora PostgreSQL 17.9 | I/O-Optimized | 2 × `db.r8g.8xlarge`, two AZs | 420.61 GiB | 30 days |
| Oregon | `app-xpo` — production | Aurora PostgreSQL 17.7 | I/O-Optimized | 2 × `db.r8g.16xlarge`, both observed in one AZ | 2,036.93 GiB | 30 days |
| Oregon | `app-anatomy` — production | Aurora PostgreSQL 17.9 | Standard | 1 × Serverless v2, 1–32 ACU | 7.25 GiB | 30 days |
| Oregon | `app-demo-cluster` — demo | Aurora PostgreSQL 17.9 | I/O-Optimized | 1 × Serverless v2, 2–16 ACU | 22.57 GiB | 30 days |
| Oregon | `app-qa` — QA global primary | Aurora PostgreSQL 17.9 | I/O-Optimized | 2 × `db.r8g.xlarge`, two AZs | 52.50 GiB | 7 days |
| Frankfurt | `app-qa-cluster` — QA global secondary | Aurora PostgreSQL 17.9 | Standard | 1 × Serverless v2, 0.5–8 ACU, no writer | 52.42 GiB | 7 days |

All Aurora clusters are encrypted, deletion-protected, private, and IAM database authentication-enabled. No live cluster is tagged as development; QA and demo are the non-production environments.

Architecture observations:

- `app-xpo` had both writer and reader in the same Availability Zone during the review. A reader exists, but the observed placement does not provide AZ-level instance failover isolation.
- Anatomy and demo are intentionally or operationally single-instance clusters.
- XPO is one Aurora PostgreSQL minor version behind the 17.9 clusters.
- Oregon QA and Frankfurt QA form a healthy global cluster, with Oregon as primary and Frankfurt as secondary.
- RDS metadata for `app` reports a stale initial database name (`app_demo`); the production application database is `app_clubready`.

### Standalone PostgreSQL

`quicksight` is PostgreSQL 13.23 on one `db.t4g.small` with 50 GiB gp3 storage, 30-day retention, encryption, deletion protection, and IAM authentication. Unlike the Aurora clusters, it is publicly accessible. This requires a network-access review but is not proof that the database is anonymously or broadly reachable.

## Aurora Standard versus I/O-Optimized

### Method

The model uses August 2026 CloudWatch read/write requests, average storage, 744 hours, observed Serverless ACU-hours, and public on-demand prices retrieved from AWS Pricing:

- Oregon Standard storage: `$0.10/GB-month`
- Oregon I/O-Optimized storage: `$0.225/GB-month`
- Oregon Standard I/O: `$0.20/million requests`
- Oregon Serverless v2: `$0.12/ACU-hour` Standard and `$0.16/ACU-hour` I/O-Optimized
- Provisioned I/O-Optimized compute carries the current class-specific premium

Formula:

```text
I/O-Optimized minus Standard =
  storage premium + compute premium - Standard I/O charge avoided
```

Positive values mean Standard was cheaper; negative values mean I/O-Optimized was cheaper.

### August Oregon results

| Cluster | Avg storage | Requests | Avoided Standard I/O | IOPT storage premium | IOPT compute premium | IOPT minus Standard | Break-even requests |
|---|---:|---:|---:|---:|---:|---:|---:|
| `app` | 415.94 GiB | 7.341B | `$1,468.20` | `$51.99` | `$1,976.06` | **`+$559.86`** | 10.140B |
| `app-demo-cluster` | 22.99 GiB | 0.043B | `$8.60` | `$2.87` | `$84.34` | **`+$78.61`** | 0.436B |
| `app-qa` | 48.69 GiB | 0.574B | `$114.80` | `$6.09` | `$247.01` | **`+$138.29`** | 1.265B |
| `app-xpo` | 1,983.08 GiB | 85.003B | `$17,000.60` | `$247.88` | `$3,952.13` | **`-$12,800.59`** | 21.000B |
| `app-anatomy` | 7.29 GiB | 0.047B | `$9.40` | `$0.91` | `$37.68` | **`+$29.19`** | 0.193B |

Conclusions:

- Keep XPO on I/O-Optimized.
- Keep `app` and Oregon QA on I/O-Optimized while payer Cost Explorer shows 100% RI coverage. The public-rate compute reduction modeled for Standard would not reduce the fixed RI commitment, while Standard I/O would become billable.
- Keep Anatomy on Standard. Its September I/O increased enough that a full month should be reviewed before revisiting the decision.
- Evaluate Standard for demo; its Serverless compute is not provisioned-instance RI-covered and August public-rate potential is approximately `$78.61/month`.

### Frankfurt QA secondary — corrected target-only analysis

A dedicated revalidation found that the earlier account-level `$121.58/month` estimate was overstated. See [FRANKFURT-QA-REEVALUATION.md](FRANKFURT-QA-REEVALUATION.md).

CloudTrail shows that Frankfurt QA was created I/O-Optimized on 2026-06-29 and changed to Standard on 2026-08-04. The original account-level model incorrectly included temporary `qa-pr-*` clusters and assumed replicated global writes would be eliminated by I/O-Optimized. Resource billing proves replicated writes remain separately charged in both modes.

Correct complete-August target quantities:

- Serverless capacity: 636.416 ACU-hours
- Mode-weighted storage: approximately 49.982 GB-month
- Ordinary storage I/O: 232.38M requests
- Replicated writes: 232.341M requests, charged in both modes
- Ordinary-I/O break-even: 178.49M requests/month

| August scenario | Public total | Net total after observed EDP |
|---|---:|---:|
| All Standard | `$197.28` | `$175.58` |
| All I/O-Optimized | `$185.43` | `$165.03` |

I/O-Optimized therefore saves approximately **`$11.86/month` public or `$10.55/month` net** on complete August usage. September 1–9 projects approximately `$30.17/month` net savings, but that period is partial and estimated. The corrected recommendation is low-priority I/O-Optimized, with a rolling 30-day ordinary-I/O threshold of approximately 180M requests.

### September caution

September 1–9 run rates differed materially from August. Anatomy in particular rose to an approximately 0.472B monthly I/O run rate, above its modeled break-even. Cost Explorer was still revising recent days during collection. Do not use the partial month as a final storage-mode decision.

## Instance and Serverless utilization

| Resource | August CPU | Memory / capacity | Connections | Interpretation |
|---|---|---|---|---|
| `app` reader | 5.42% avg, 99.12% peak | 64.17 GiB avg free, 6.20 GiB min | 350 avg, 3,292 peak | Connection concentration and transient peaks need query/pool analysis |
| `app` writer | 7.42% avg, 100% peak | 67.81 GiB avg free, 57.07 GiB min | 19.5 avg, 193 peak | Average CPU alone overstates rightsizing headroom |
| XPO pair | 20.20–21.47% avg, 98.6–99.3% peak | 133–135 GiB avg free, 55–88 GiB min | 2,192–2,581 peaks | High I/O and sharp peaks; no simple downsizing case |
| QA pair | 8.40–11.25% avg, ~99.7% peak | ~6.2 GiB avg free, ~2.0 GiB min | 384–421 peaks | Memory and peaks constrain rightsizing |
| Anatomy | 3.2% avg | 1.266 avg ACU, 16 observed peak | 15.5 avg, 155 peak | Review minimum and burst requirements only with workload owner |
| Demo | 4.1% avg | 2.833 avg ACU, 16 peak | 16.7 avg, 86 peak | IOPT mode and 2-ACU minimum are cost-review targets |
| Frankfurt QA | Serverless | 0.855 avg ACU; historical metric peak exceeded current max | Not material to this decision | Configuration changed or metric history spans an older limit |
| `quicksight` | 8.83% avg, 97% peak | 0.527 GiB avg free, 0.155 GiB min | 0.36 avg, 29 peak | Monitor memory headroom |

Performance Insights is enabled but retains only seven days. Query-level load and I/O causes were not analyzed. Enhanced Monitoring coverage is inconsistent across instances.

## Logical databases and largest objects

Sizes below are approximate PostgreSQL catalog values. Partition-family totals aggregate child partitions and include indexes. They are not exact row counts or evidence that data can be deleted.

### `app`

- `app_clubready`: approximately 407 GiB
- `app_dashboard`: approximately 19 GiB
- Additional views database content: approximately 1.9 GiB

Largest `app_clubready` partition families:

| Relation family | Approx. total | Approx. live rows | Notes |
|---|---:|---:|---|
| `clubready_client_member_statuses` | 98 GiB | 279M | Mostly 256 partitions; index-heavy children |
| `clubready_attendances` | 74 GiB | 71M | Partitioned |
| `clubready_client_contact_logs` | 64 GiB | 139M | Partitioned |
| `reports.multi_location_corporate_report` | 21 GiB | Not estimated | Report/date partitioning |
| `daily_metric_organization_items` | 20 GiB | Not estimated | Retention candidate subject to product policy |
| `clubready_sales` | 19 GiB | Not estimated | Partitioned |
| `clubready_checkins` | 17 GiB | Not estimated | Partitioned |

The top five consume approximately 277 GiB, about 68% of `app_clubready`.

`app_dashboard` is unusually concentrated:

| Relation | Approx. total |
|---|---:|
| `delayed_jobs` | 13 GiB |
| `worker_logs` | 3.94 GiB |

Together they are about 89% of the dashboard database. Determine whether completed/failed job history and worker logs have an explicit retention requirement.

### `app-xpo`

`app_xpo` is approximately 2,011 GiB. Approximate schema totals include `public` 1,758 GiB, `reports` 204 GiB, `stats` 26 GiB, and smaller event/views/prediction schemas.

| Relation family | Approx. total | Table / index observation | Approx. live rows |
|---|---:|---|---:|
| `clubready_client_member_statuses` | 557 GiB | ~192 GiB table / ~405 GiB indexes | 1.58B |
| `clubready_attendances` | 444 GiB | ~169 GiB table / ~307 GiB indexes | 538M |
| `clubready_client_contact_logs` | 319 GiB | ~218 GiB table / ~125 GiB indexes | 659M |
| `clubready_sales` | 124 GiB | Partition family | Not estimated |
| `daily_metric_organization_items` | 98 GiB | Partition family | Not estimated |
| `reports.multi_location_corporate_report` | 67 GiB | Report partitions | Not estimated |
| `reports.xpo_multi_location_corporate_report_339` | 55 GiB | 1,393 children | Not estimated |
| `clubready_checkins` | 46 GiB | Partition family | Not estimated |
| `versions` | 31 GiB | Unpartitioned | Not estimated |
| `clubready_clients` | 26 GiB | Partition family | Not estimated |

The five largest families are approximately 1.54 TiB, about 77% of the database. Member-status and attendance families are especially index-heavy. The next safe work is to map partition keys and retention boundaries and measure index use—not to run broad deletes, `VACUUM FULL`, `REINDEX`, or partition detaches.

### `app-qa`

The QA database is approximately 52 GiB. Its largest families are contact logs (~14 GiB), member statuses (~12 GiB), and attendances (~10 GiB), together about 69% of the database.

## Partitioning and maintenance interpretation

The major ClubReady families are already hash-partitioned by store/location, usually into 256 children. Report families use date-oriented range partitions. This differs from the unpartitioned PIQ telemetry tables and changes the safe cleanup strategy:

- Date-based report partitions may support efficient retention by detaching/dropping whole expired partitions after dependency and compliance review.
- Hash-partitioned operational families require a date/retention key analysis inside each partition; partition existence alone does not enable age-based removal.
- High index-to-table ratios justify `pg_stat_user_indexes`, query-plan, and Performance Insights analysis before dropping or rebuilding any index.
- Catalog dead-tuple counters were not reliable enough in the reader sessions to substantiate bloat. Do not infer a need for `VACUUM FULL` or `REINDEX` from table size alone.

## Backup and snapshot findings

### Native plus AWS Backup overlap

Native Aurora retention is 30 days for `app`, XPO, Anatomy, and demo, and seven days for both QA clusters. AWS Backup plan `Backup-Production-Plan` runs daily and retains 30 days in `iKizmet-Production-Vault` for all five Oregon Aurora clusters selected by `Backup=true`.

At review time, the vault contained 150 completed Aurora recovery points: 30 per Oregon cluster. Therefore:

- `app`, XPO, Anatomy, and demo each have 30-day native retention plus 30 AWS Backup points.
- Oregon QA has seven-day native retention plus 30 AWS Backup points.
- Backup Vault Lock is not enabled.
- A legacy vault has one old `app` Aurora recovery point without a calculated deletion date.

Overlap is not automatically waste. AWS Backup may provide centralized policy, independent permissions, or compliance controls. Document required recovery-point objective, retention, isolation, and restore workflow before consolidating anything.

### Manual snapshots requiring ownership review

The account contains old or special-purpose manual snapshots for `app`, XPO, data bridge, pre-final/final migrations, Anatomy, demo, standalone reporting, and one unencrypted zero-size artifact in `us-east-1`. Names include explicit warnings such as `do-not-delete`.

Aurora snapshots are incremental; their displayed logical allocated sizes cannot be summed to calculate billed physical bytes. No snapshot should be deleted until an owner confirms purpose, dependencies, retention, legal/compliance needs, and a restore test or replacement recovery point.

## Validated opportunities and unresolved questions

| Opportunity | Public-rate or billed signal | Confidence | Required validation |
|---|---:|---|---|
| Keep `app` IOPT while RI-covered | Avoids adding Standard I/O under fixed RI commitment | High billing confidence | Reevaluate if RI coverage or renewal changes |
| Keep Oregon QA IOPT while RI-covered | Standard estimated ~$97 net/month more | High billing confidence | Reevaluate if RI coverage changes |
| Move demo to Standard | ~$78.61/month public-rate | High economically | Recent full month, workload owner approval |
| Move Frankfurt QA secondary to IOPT | ~$11.86 public / ~$10.55 net per complete August | Medium-high | Rolling ordinary I/O above ~180M, Terraform plan, cooldown and replication checks |
| Keep XPO IOPT | Avoids ~$12,800.59/month | High | Continue monthly break-even monitoring |
| Backup-policy consolidation | `$1,558.82` August Aurora backup charge | Medium | Recovery/compliance policy and per-source billing attribution |
| Dashboard job/log retention | ~17 GiB logical | High storage concentration | Row-age distribution, application dependencies, retention policy |
| XPO partition/index review | ~1.54 TiB in top five families | High concentration, unknown savings | Partition keys, date distribution, index usage, compliance |
| Serverless minimum review | Demo avg 2.833 ACU; Anatomy avg 1.266 | Medium | Latency, auto-pause compatibility, scheduling, complete workload cycle |
| Quicksight public access | Security exposure, not a cost estimate | High configuration confidence | Network path, consumers, security-group and public-access need |

## Constraints and exclusions

- No RI or Savings Plan purchase, exchange, renewal, or coverage recommendation is included.
- No storage mode, instance class, Serverless range, backup retention, snapshot, AZ placement, network setting, engine version, schema, partition, index, or row data was changed.
- No table payload or date distribution was sampled; catalog estimates alone do not authorize retention changes.
- Snapshot logical sizes are not additive billed storage.
- CloudWatch monthly models use workload observations; Cost Explorer and contractual discounts determine realized invoice impact.
