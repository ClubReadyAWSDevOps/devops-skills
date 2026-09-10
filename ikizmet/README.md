# iKizmet AWS RDS Review

Read-only cost, architecture, storage, backup, and PostgreSQL catalog research for the iKizmet AWS account.

## Scope

- AWS account: `410878187014` (`sa-ikizmet`)
- Primary region: `us-west-2`
- Secondary region: `eu-central-1` for the QA global-database secondary
- Review date: 2026-09-10
- Latest complete cost month: August 2026
- Services: Aurora PostgreSQL, standalone RDS PostgreSQL, AWS Backup, CloudWatch, Cost Explorer, and metadata-only PostgreSQL catalogs
- Excluded: Reserved Instance and Savings Plan purchasing because commitments are managed separately

## Documents

- [IKIZMET-RDS-FINDINGS.md](IKIZMET-RDS-FINDINGS.md) — evidence, topology, costs, storage economics, utilization, database sizes, largest tables, and backup inventory
- [IKIZMET-SAVINGS-PLAN.md](IKIZMET-SAVINGS-PLAN.md) — prioritized validation and change plan with rollback and approval gates
- [FRANKFURT-QA-REEVALUATION.md](FRANKFURT-QA-REEVALUATION.md) — corrected target-only Frankfurt Standard versus I/O-Optimized analysis
- [XPO-STANDALONE-TABLE-AUDIT.md](XPO-STANDALONE-TABLE-AUDIT.md) — read-only stale-data audit of all non-partitioned app_xpo tables
- [AWS-BACKUP-RDS-CHANGE-2026-09-10.md](AWS-BACKUP-RDS-CHANGE-2026-09-10.md) — executed AWS Backup RDS exclusion, verification evidence, impact, and rollback

## Current decisions and completed changes

1. Keep `app-xpo` on Aurora I/O-Optimized. August workload saved an estimated `$12,800.59/month` at public rates compared with Standard.
2. Keep `app` and Oregon `app-qa` on I/O-Optimized while their provisioned compute remains 100% RI-covered; Standard would add billable I/O without reducing the fixed RI commitment.
3. Keep `app-anatomy` on Standard while monitoring its September I/O increase.
4. Evaluate Standard for `app-demo-cluster`; August public-rate potential is about `$78.61/month` and Serverless compute is not RI-covered.
5. Frankfurt `app-qa-cluster` slightly favors I/O-Optimized: `$10.55/month` net savings on complete August workload and a partial-September projection of `$30.17/month`. This is low priority; replicated writes remain billed in both modes.
6. Do not infer rightsizing from average CPU. Every major provisioned cluster had near-100% spikes, and QA has limited memory headroom.
7. Completed 2026-09-10: excluded all Oregon RDS clusters and DB instances from future AWS Backup selection. Native RDS backups remain enabled; the 150 existing Aurora recovery points remain and will expire under their 30-day lifecycle.
8. Continue the ownership review for old manual snapshots and the legacy recovery point; none were deleted by the AWS Backup selection change.
9. Prioritize retention and index-use analysis for XPO partition families and retention analysis for `app_dashboard.delayed_jobs` and `worker_logs`.

## Safety and evidence boundaries

The cost and database audit itself was read-only. After separate explicit confirmation, one AWS configuration change was made on 2026-09-10: the immutable backup selection was safely replaced with a verified selection that excludes Oregon RDS resources while preserving the `Backup=true` condition for non-RDS resources. No recovery point, native backup, snapshot, storage mode, instance, index, partition, schema, or row data was changed or deleted.

Database inspection was catalog-only over TLS and read-only transactions. Credential values and customer row payloads were not printed or stored. Endpoint names and secret values are intentionally omitted from these documents.

All savings are estimates unless explicitly identified as billed Cost Explorer amounts. Storage-mode estimates use August 2026 CloudWatch workload and current public on-demand rates; actual invoices depend on commitments, discounts, workload changes, and billing semantics.
