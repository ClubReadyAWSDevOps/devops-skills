# iKizmet RDS Savings Plan

Status: AWS Backup RDS exclusion executed 2026-09-10; all remaining changes require separate approval  
Based on evidence collected: 2026-09-10  
Latest complete cost month: August 2026  
Executed change: [AWS-BACKUP-RDS-CHANGE-2026-09-10.md](AWS-BACKUP-RDS-CHANGE-2026-09-10.md)

## Objectives

1. Reduce avoidable Aurora storage-mode and backup cost without degrading availability or recovery posture.
2. Establish explicit retention for dashboard jobs/logs, report partitions, and high-volume ClubReady history.
3. Improve visibility into I/O, connection spikes, memory pressure, and index use before rightsizing.
4. Keep Reserved Instance and Savings Plan purchasing outside this plan.

## Guardrails

- Every AWS or database mutation requires separate approval, a named owner, a change window, and a rollback procedure.
- Recheck account, region, cluster identifier, engine, storage mode, global-cluster role, tags, and recent backups immediately before a change.
- Never test destructive retention SQL against production first.
- Never delete a snapshot or recovery point because its name or date appears stale.
- Do not perform broad `DELETE`, `VACUUM FULL`, `REINDEX`, `DROP`, or partition detach based only on catalog size.
- Treat customer retention and compliance requirements as prerequisites, not cleanup details.
- Compare at least one complete recent month to August before changing a storage configuration.

## Phase 1 — no-risk measurement

### 1. Build a monthly storage-mode scorecard

For each Aurora cluster, record:

- average `VolumeBytesUsed`
- total `VolumeReadIOPs` plus `VolumeWriteIOPs`
- provisioned instance-hours or Serverless ACU-hours
- public Standard and I/O-Optimized counterfactuals
- actual billed usage types and discounts separately
- break-even request volume and margin

Initial August position, corrected with payer RI coverage and target-only Frankfurt attribution:

| Cluster | Current | August decision signal | Monthly evidence |
|---|---|---|---:|
| `app-xpo` | I/O-Optimized | Keep IOPT | IOPT cheaper by ~$12,800.59 public-rate |
| `app` | I/O-Optimized | Keep IOPT while RI-covered | 100% RI coverage; Standard would add billed I/O without reducing fixed commitment |
| `app-qa` Oregon | I/O-Optimized | Keep IOPT while RI-covered | 100% RI coverage; Standard estimated ~$97 net/month more under current billing |
| `app-demo-cluster` | I/O-Optimized | Evaluate Standard | Standard cheaper by ~$78.61 public-rate |
| `app-anatomy` | Standard | Keep and monitor | Standard cheaper by ~$29.19 public-rate in August |
| `app-qa-cluster` Frankfurt | Standard | Low-priority IOPT candidate | IOPT cheaper by ~$11.86 public / ~$10.55 net on target August workload |

Exit criterion: two complete months agree on direction, or the owner explicitly accepts a change based on one month plus a documented sensitivity range.

### 2. Improve observability before rightsizing

- Retain Performance Insights history long enough to cover weekly and month-end workload cycles where cost-effective.
- Standardize Enhanced Monitoring where host-level memory/process evidence is needed.
- Identify why the `app` reader reached 3,292 connections and whether pooling, leaks, fan-out, or reporting caused the concentration.
- Capture top I/O and database-load SQL for XPO, `app`, and QA without persisting customer literals.
- Review Serverless capacity and latency at the observed demo and Anatomy peaks.

Exit criterion: workload owners can explain peak CPU, connection, memory, and I/O periods and identify service-level constraints.

## Phase 2 — low-complexity storage-mode candidates

Change one cluster at a time. Before each change, export the prior 35 days of I/O, storage, ACU/instance-hours, latency, CPU, memory, connection, and cost evidence.

### Candidate A: demo to Standard

- Modeled August savings: ~$78.61/month.
- Reason: 43M requests were far below the 436M break-even.
- Validate: complete recent month, demo workload calendar, and whether any load test explains September changes.
- Rollback trigger: observed request run rate persistently exceeds break-even or billed daily run rate rises beyond the agreed threshold.

### Oregon QA and `app`: keep I/O-Optimized while RI-covered

Payer Cost Explorer confirms 100% August RI coverage for `db.r8g.xlarge` and `db.r8g.8xlarge`. The fixed RI commitment does not disappear when the storage mode changes. Under current billing, Standard would add ordinary I/O charges without delivering the public-rate compute reduction used in the initial model.

- Keep Oregon QA I/O-Optimized; Standard is estimated to cost approximately `$97 net/month` more under current RI-aware billing.
- Keep `app` I/O-Optimized while its compute remains fully RI-covered.
- Reevaluate only if RI coverage, commitment ownership, or renewal terms change.

### Frankfurt QA secondary to I/O-Optimized

- Correct complete-August target savings: approximately `$11.86/month` public or `$10.55/month` net.
- September 1–9 projection: approximately `$30.17/month` net, but partial and estimated.
- Reason: 232.38M ordinary August I/O requests exceeded the 178.49M break-even by 30.2%.
- Replicated writes remain separately billed in both modes and do not belong in the avoided-I/O calculation.
- Operational threshold: keep I/O-Optimized while rolling 30-day ordinary I/O remains above approximately 180M.
- Validate: apply through Terraform, record cooldown/rollback timing, verify global replication health, and compare a complete post-change invoice month.

Do not change XPO from I/O-Optimized. Its 85B August requests were approximately four times its public-rate break-even, and part of its provisioned usage was not RI-covered.

## Phase 3 — Serverless configuration review

### Demo

Demo averaged 2.833 ACU and reached 16 ACU. Its current 2-ACU minimum may be justified by latency or background work, but should be tested against lower-minimum or auto-pause behavior during known idle windows.

### Anatomy

Anatomy averaged 1.266 ACU and reached 16 ACU. Keep Standard storage. Review minimum capacity only after understanding the September write-I/O increase and startup/latency requirements.

Procedure:

1. Map hourly ACU, connection, latency, and job schedules for at least 30 days.
2. Define maximum acceptable cold-start and request latency.
3. Test the proposed range in a non-production equivalent.
4. Change one minimum/auto-pause setting at a time with alarms and rollback values recorded.

No savings value is claimed until idle-time and latency evidence is collected.

## Phase 4 — backup and snapshot policy

### Required policy decisions

For each cluster, document:

- point-in-time recovery window
- daily/monthly retention
- separate-account or vault isolation requirement
- immutability/Vault Lock requirement
- restore-time objective and tested restore process
- owner and compliance basis

Then classify native backups, AWS Backup points, and manual snapshots as complementary, required duplicates, or candidates for consolidation.

### Inventory actions

- Investigate the old recovery point without a calculated deletion date in the legacy vault.
- Assign owners and purpose to each manual snapshot, especially `do-not-delete`, migration/final, pre-upgrade, repartition, and data-bridge snapshots.
- Identify dependencies such as restores, shared snapshots, cross-region copies, audits, and legal holds.
- Attribute billed backup growth by cluster and recovery-point source as far as AWS metrics permit.
- Run a restore test before reducing any recovery path.

Potential is material because August Aurora backup cost was `$1,558.82`, but no savings amount is assigned until policy and billing attribution are complete.

## Phase 5 — database retention and index analysis

### Dashboard jobs and logs

`app_dashboard.delayed_jobs` (~13 GiB) and `worker_logs` (~3.94 GiB) consume about 89% of the dashboard database.

Read-only discovery:

1. Identify time/status columns, dependencies, foreign keys, triggers, and application queries.
2. Produce row-count and size distributions by month and job state without selecting payloads.
3. Define retention for successful jobs, failed jobs, retry metadata, and worker logs.
4. Estimate reclaimable storage and backup impact.
5. Test bounded cleanup in a restored non-production copy.

Prefer batched retention or partition lifecycle design over one large production delete. PostgreSQL space-return behavior and Aurora volume reclamation must be measured in the test copy.

### Report partitions

Map date boundaries and usage for `reports.multi_location_corporate_report` and XPO report families. If whole range partitions are outside approved retention, partition detach/archive/drop can be safer than row deletes, but only after dependency and restore validation.

### High-volume ClubReady families

For XPO member statuses, attendances, contact logs, sales, and daily metrics:

- map hash partition keys and date columns
- measure age distribution without selecting business payloads
- collect `pg_stat_user_indexes`, normalized query plans, and Performance Insights evidence
- identify duplicate, unused, or overlapping indexes
- estimate write amplification and cache cost of candidate indexes
- validate any index removal through a full workload cycle in a clone or restored environment

Index-heavy storage is an investigation signal, not permission to drop indexes.

## Phase 6 — availability and security follow-ups

These are not direct savings items but affect whether cost changes are safe:

- Correct or explain XPO writer/reader placement in one Availability Zone.
- Review whether single-instance Anatomy and demo meet their availability requirements.
- Review the public-access requirement, security groups, and consumers for standalone `quicksight`.
- Plan the Aurora PostgreSQL minor-version alignment for XPO.
- Correct stale `DatabaseName` metadata/documentation for `app` where practical.

## Change validation template

For each approved change, record:

1. Exact account, region, cluster, global role, engine, tags, and current value.
2. Approval, owner, maintenance window, and rollback value.
3. Pre-change 35-day metrics and normalized billed costs.
4. Backup/recovery verification.
5. Change event timestamp.
6. Post-change availability, replication, latency, errors, CPU, memory, connections, I/O, and storage.
7. Seven-day early review and one-complete-month financial review.
8. Final decision to keep or roll back.

## Prioritized sequence

1. Start monthly break-even reporting and improve Performance Insights/connection evidence.
2. Validate and trial demo Standard because it is low-risk and far below break-even.
3. Validate Oregon and Frankfurt QA storage modes together as a global-database change set.
4. Revalidate `app` over another full month, then decide on Standard.
5. Complete backup policy and snapshot ownership review; restore-test before consolidation.
6. Define and test dashboard job/log retention in a restored copy.
7. Analyze XPO report retention and index use; do not change XPO from I/O-Optimized.
8. Address XPO AZ concentration and Quicksight public access through separate architecture/security changes.

## Success measures

- Storage-mode changes realize their modeled direction over a complete billing month.
- No regression in availability, replication, latency, error rate, or recovery objectives.
- Every backup and manual snapshot has an owner, purpose, and expiry or explicit retention basis.
- Dashboard and report retention is policy-driven, repeatable, and tested outside production.
- XPO index/partition work is backed by usage evidence and measured before/after results.
- RI and Savings Plan decisions remain with their designated third-party owner.
