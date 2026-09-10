# app_xpo Standalone (Non-Partitioned) Table Stale-Data Audit

Review date: 2026-09-10  
AWS account: `410878187014` (`sa-ikizmet`)  
Region: `us-west-2`  
Cluster: `app-xpo` (Aurora PostgreSQL 17.7)  
Database: `app_xpo`  
Scope: every standalone user table, explicitly excluding all partition parents and children  
Status: read-only; no AWS, database, or schema change made

## Method and safeguards

The audit connected only to the reader endpoint over TLS using a short-lived IAM token for `iam_user_ro`, confirmed the instance was a replica, and ran every probe in a read-only transaction with statement and lock timeouts. No endpoints, tokens, secrets, or row payloads were emitted; temporal probes returned dates only.

No `DDL`, `DML`, `ANALYZE`, `VACUUM`, `REINDEX`, or `EXPLAIN ANALYZE` was run. Only catalog reads, `pg_stats`, plain `EXPLAIN`, and index-safe `ORDER BY ... LIMIT 1` date probes were used.

The strict standalone set is defined as `pg_class.relkind='r'`, `relispartition=false`, non-system schema, and not present on either side of `pg_inherits`.

## Scope proof: partitions excluded

| Class | Count |
|---|---:|
| Partitioned parents (`relkind='p'`) — excluded | 21 |
| Partition children (`relispartition=true`) — excluded | 4,964 |
| Ordinary `r` (not partition) | 13,826 |
| Inheritance children — excluded | 5,452 |
| Inheritance parents — excluded | 38 |
| Inheritance-excluded union | 5,488 |
| **Strict standalone tables (final set)** | **8,338** |

Arithmetic check: 13,826 − 5,488 = 8,338. All partition parents and children are excluded by construction.

## Key finding: non-partitioned data is a small storage target

Total standalone storage is approximately **94.9 GiB**, versus the roughly 2 TiB cluster that is dominated by partitioned families. Stale, fully dormant standalone data is only about **1.55 GiB**. Non-partitioned tables are therefore not a material cost lever compared with partitioned retention and RI coverage.

Size distribution (total relation size):

| Bucket | Tables |
|---|---:|
| ≤ 1 MiB | 6,974 |
| > 1 MiB – 64 MiB | 1,287 |
| > 64 MiB – 1 GiB | 57 |
| > 1 GiB – 10 GiB | 19 |
| > 10 GiB | 1 |

By schema:

| Schema | Tables | Approx. size |
|---|---:|---:|
| `public` | 160 | 62.35 GiB |
| `stats` | 76 | 25.92 GiB |
| `views` | 7,991 | 3.27 GiB |
| `predictions` | 6 | 2.83 GiB |
| `llm_orchestrator` | 7 | 0.54 GiB |
| `reports` | 98 | 0.02 GiB |

## Access constraint scoping all row-level conclusions

`iam_user_ro` has row and `pg_stats` access only to `public` and `llm_orchestrator`. It cannot read rows or statistics for `stats` (76 tables), `predictions` (6), `reports` (98), or `views` (7,991). For those schemas only catalog metadata is available; their temporal bounds are **unknown due to access restriction**, not absent.

On the reader, write and maintenance counters are unusable: `stats_reset` is null, no table has an analyze/vacuum timestamp, and insert/update/delete/live/dead counters are zero. Only replica-local scan counters move. **Reader statistics cannot prove writer inactivity.** Staleness conclusions therefore rely on temporal-column bounds, not activity counters.

## Temporal coverage

- 8,301 of 8,338 tables have at least one temporal column.
- 8,020 have a leading valid non-partial B-tree temporal index, making them safe exact-probe candidates.
- Exact probing was only possible in the two accessible schemas; other schemas fell back to metadata only.

## Stale candidates (accessible schemas)

Reference date: 2026-09-10.

| Table | Size | Rows | Evidence | Classification |
|---|---:|---:|---|---|
| `public.delayed_jobs_postponed` | 1.43 GiB | ~43K | Histogram max of `created_at`/`run_at`/`updated_at` ≈ 2025-11-20; ~10 months idle | High-confidence stale review candidate (approximate) |
| `public.versioned_objects` | 0.12 GiB | ~362K | Inserts stopped ≈ 2024-07-24; last update ≈ 2024-12-02 | Stale, dormant, small |

Combined fully dormant standalone storage is approximately **1.55 GiB**. This is a rough figure, not guaranteed reclaimable bytes, and excludes index and bloat effects.

## Mixed-age active tables (retention-trim candidates, not stale tables)

These tables are active but hold long historical tails. Trimming requires a retention policy, not table removal.

| Table | Size | Observed range | Bound method |
|---|---:|---|---|
| `public.versions` | 31.07 GiB | 2020 → 2026 | Likely PaperTrail audit history |
| `public.corporate_report_logs` | 2.79 GiB | 2023 → 2026 | Approximate |
| `public.emails` | 1.39 GiB | 2019 → 2026 | Exact |
| `public.login_activities` | 1.01 GiB | 2019 → 2026 | Exact |

## Active — keep

`raw_data_links` (9.01 GiB, current to 2026-09-10), `worker_logs` (2.75 GiB, already self-purging at ~1 month), `active_storage_blobs`/`active_storage_attachments`, `organization_goals`, `llm_orchestrator.messages`, `stripe_invoices` (current to 2026-09-08), and the `clubready_*` reference/configuration tables.

## Large unknowns (material but access-restricted)

- `stats.*`: 52 tables over 64 MiB, about 25.9 GiB. Largest include `classes_utilization_daily` (2.32 GiB) and `sales_by_staff_net`/`sales_by_staff_gross_daily` (~1.85 GiB each). The `*_daily` tables expose a `day` date key with strong retention potential; `*_monthly` expose only `updated_at`. Not assessable as `iam_user_ro`.
- `predictions.*`: churn/utilization/member-revenue tables, about 2.83 GiB. Access-restricted.
- `views.*`: 7,991 tables, about 3.27 GiB total; tiny per table and low storage priority. Access-restricted.

## Activity snapshots

Two reader snapshots about 1,969 seconds apart (extended by a transient private-DNS outage) showed Δseq_scan +54,928 and Δidx_scan +5.22B, with zero visible insert/update/delete/live/dead movement. This reflects heavy replica reads and does not prove writer inactivity.

## Dependencies and risks

- `active_storage_blobs`/`active_storage_attachments` are Rails ActiveStorage and foreign-key linked; deletions must go through the application layer.
- `versions` is likely PaperTrail audit history with possible compliance/retention requirements.
- `delayed_jobs_postponed` dormancy should be confirmed with the application owner; it may be a retired feature or a stuck queue.
- All row-level reasoning in restricted schemas is blocked without a scoped read grant.

## Recommended clone-only follow-ups

1. Restore a snapshot clone and run exact min/max and per-year histograms for `delayed_jobs_postponed`, `versioned_objects`, and the log tails (`versions`, `emails`, `login_activities`, `corporate_report_logs`).
2. On the clone, obtain `stats.*_daily` `day`-column distributions to size date-based retention.
3. Confirm application ownership and retention policy, and validate foreign-key and trigger dependencies, before any deletion.
4. Consider granting read access to a scoped reader to remove the `stats`/`predictions`/`reports`/`views` blind spot in a future pass.

## Bottom line

Non-partitioned `app_xpo` data offers little direct storage savings: about 94.9 GiB total and roughly 1.55 GiB clearly dormant. The larger opportunities remain partitioned-family retention, `stats.*_daily` retention (pending access), RI coverage, and Serverless/PR-environment lifecycle — not standalone-table cleanup.
