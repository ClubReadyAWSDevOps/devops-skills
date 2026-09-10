# PIQ Database Operations

This directory records the verified PIQ Aurora findings and the design for a repeatable development-database refresh process.

## Scope

- AWS account: `397665031723`
- Region: `us-west-2`
- Production cluster: `piqmaster-cluster-1`
- Current development cluster: `piqdev-cluster1-2026-08-24`
- Engine: Aurora MySQL 8.0
- Review date: 2026-09-10

## Documents

- [PIQ-DEV-FINDINGS.md](PIQ-DEV-FINDINGS.md) — cost, storage, I/O, backup, table-size, retention, and completed-change findings.
- [CODEBUILD-REFRESH-PLAN.md](CODEBUILD-REFRESH-PLAN.md) — proposed guarded workflow for creating a development database from production and removing production data.

## Current decisions

1. Keep PIQ on Aurora Standard storage. I/O-Optimized is more expensive at the observed storage size and I/O volume.
2. Treat the full-size development dataset as the primary storage optimization opportunity.
3. `piqapp.api_logs` was truncated on the development cluster on 2026-09-10 after explicit confirmation.
4. `piqapp.power_series` is inactive on development but has not been changed.
5. Reserved Instances and Savings Plans are excluded from this work because a third party manages them.
6. No future automation may target production for destructive SQL. A newly created development target must pass account, cluster-ID, endpoint, tag, and database safety checks first.

## Important design decision

If the desired development database should contain **schema only**, do not copy the approximately 10 TiB production volume and then truncate every table. Export and restore schema only.

If development needs selected production-derived reference data, use an Aurora clone or snapshot restore and apply a version-controlled action manifest that explicitly identifies tables to retain, truncate, subset, or sanitize.

## Security

Do not commit database passwords, secret values, generated endpoints, customer data, or query results containing personal data. Runtime credentials must come from AWS Secrets Manager and must never be printed by CodeBuild.
