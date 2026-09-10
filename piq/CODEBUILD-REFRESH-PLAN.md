# PIQ Development Database Refresh Plan

Status: design only. No executable refresh automation has been created yet.

## Goal

Create a repeatable, auditable process that provides a safe PIQ development database based on the production schema or data while minimizing storage cost and preventing any destructive action against production.

The workflow is expected to run through AWS CodeBuild, with manual approval or a controlled orchestrator initiating each refresh.

## First decision: schema-only or reduced production copy

### Option A — schema-only development database

Use this when every application table should be empty.

Recommended approach:

1. Export production schema only.
2. Create a new empty Aurora development cluster.
3. Restore schema definitions, routines, views, and required seed/configuration data.
4. Run migrations and validation.

Do **not** copy a 10+ TiB production volume merely to truncate every table. Schema-only creation is faster, cheaper, and avoids handling production customer data in development.

### Option B — curated production-derived copy

Use this when development requires selected reference data or recent representative records.

Preferred same-account, same-region source-copy candidate: Aurora cloning. Aurora uses copy-on-write, so an initial clone requires minimal additional storage and diverging pages are charged as source or clone data changes. Validate the cost behavior of truncating or rebuilding multi-terabyte tables in a clone during a proof of concept.

Reference: [AWS — Cloning a volume for an Aurora DB cluster](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Clone.html).

Fallback: restore a production cluster snapshot to a new temporary cluster. Snapshot restore creates a new cluster and endpoint; it does not overwrite the existing development cluster.

## Proposed architecture

```text
Manual approval / controlled scheduler
                |
                v
        CodeBuild refresh project
        - VPC private subnets
        - dedicated security group
        - dedicated IAM role
                |
                +--> RDS API: create clone/restore target
                +--> Secrets Manager: runtime credentials
                +--> MySQL: sanitize/reduce target only
                +--> CloudWatch/SNS: logs and outcome
                |
                v
   Temporary target: piqdev-refresh-<build-id>
                |
        validation + approval
                |
                v
    update dev secret/DNS/config pointer
                |
        rollback retention window
                |
                v
       delete previous dev cluster
```

A Step Functions wrapper is optional but preferable for long waits, approval, retries, and cleanup. CodeBuild can own SQL and validation while the state machine owns RDS lifecycle operations.

## Safety invariants

The build must stop before any SQL unless every condition passes:

1. AWS account is exactly `397665031723`.
2. Region is exactly `us-west-2`.
3. Target cluster ID starts with `piqdev-refresh-` and includes the current build ID.
4. Target cluster is not `piqmaster-cluster-1`.
5. Target endpoint exactly matches the endpoint returned by `DescribeDBClusters` for the temporary target.
6. Target has tags `Environment=development`, `ManagedBy=codebuild`, and `RefreshBuild=<build-id>`.
7. Engine is Aurora MySQL 8.0 at an approved version.
8. SQL `SELECT DATABASE()` returns the expected database.
9. Production endpoints and cluster identifiers are maintained in an explicit denylist.
10. The action manifest is version controlled, reviewed, and checksum-logged.
11. Secret values, SQL payloads, and customer data are never printed.
12. Destructive SQL credentials exist only for the temporary development target.

Production credentials should be read-only if production SQL access is required at all. RDS API permissions to delete or modify production must not be granted to the CodeBuild role.

## Proposed workflow

### Phase 1 — request and approval

Required input:

- Refresh mode: `schema-only` or `curated-copy`
- Source production cluster identifier
- Temporary target identifier
- Approved action-manifest version
- Retention cutoff parameters, if any
- Approval identity and change ticket

Reject ad hoc table names and arbitrary SQL passed as build parameters.

### Phase 2 — preflight

1. Call STS and validate account and role ARN.
2. Describe the source cluster and validate production identity.
3. Verify source and target identifiers are different.
4. Verify no target with the requested build ID already exists, or resume it idempotently.
5. Verify required subnets, security groups, parameter groups, KMS key, and Secrets Manager entries.
6. Record source engine version, parameter group, backup configuration, and cluster size.
7. Refuse execution if any required tag or denylist check fails.

### Phase 3 — create target

For schema-only mode:

1. Create an empty Aurora MySQL target at the approved small development instance class.
2. Export schema without data from production using read-only credentials, or use a version-controlled canonical schema.
3. Restore schema to the temporary target.

For curated-copy mode:

1. Create an Aurora clone, or restore the approved production snapshot.
2. Create a small development instance in the temporary cluster.
3. Wait for cluster and instance availability with bounded retries.
4. Obtain the generated endpoint from the RDS API; never accept it as user input.
5. Create or rotate a target-only Secrets Manager credential.

### Phase 4 — sanitize and reduce

Use a declarative manifest rather than embedded one-off SQL.

Proposed action types:

- `truncate` — retain schema, remove all rows.
- `retain_after` — rebuild a table with records after an approved cutoff.
- `subset` — retain a deterministic representative subset.
- `redact` — replace sensitive columns while retaining relational shape.
- `retain` — explicitly preserve an approved table.
- `seed` — restore controlled non-production test/configuration data.

Every application table must appear exactly once in the manifest. The build fails on an unknown or unclassified table.

### Initial PIQ table classification draft

| Table | Proposed action | Status |
|---|---|---|
| `piqapp.api_logs` | `truncate` | Evidence supports; completed manually on current dev |
| `piqapp.power_series` | `truncate` or `retain_after` | Decision required |
| `piqapp.hr_series` | `truncate` or `retain_after` | Activity/date review required |
| `piqapp.rower_series` | `truncate` or `retain_after` | Activity/date review required |
| `piqapp_emails.emails` | `truncate` or redact/subset | Decision required; contains message bodies |
| `piqapp.class_sync_logs` | `truncate` | Validate application dependency |
| `piqapp.clubready_reservation_log` | `truncate` or `retain_after` | Validate test requirements |
| Reservation/core tables | `subset`, `redact`, or `retain` | Product/team decision required |
| Migration/schema-version tables | `retain` | Usually required |
| Lookup/configuration tables | `retain` or `seed` | Identify explicitly |

This is not yet an approved execution manifest.

### Phase 5 — SQL execution controls

1. Connect only to the generated temporary endpoint through the CodeBuild VPC.
2. Repeat target safety checks inside the database session.
3. Set finite connection, read, write, and metadata-lock timeouts.
4. Log statement category, table, start/end time, and affected metadata—but not data or credentials.
5. Execute one manifest action at a time and checkpoint completion.
6. Treat MySQL DDL as non-transactional/autocommitting; resume idempotently after failure.
7. Do not perform multi-billion-row in-place deletes.
8. For large recent-only tables, build a compact replacement, validate it, atomically rename, then retain the old table until approval or drop it within the temporary target.
9. Never run `OPTIMIZE TABLE` on multi-terabyte tables as a routine cleanup step.

For a true all-empty schema, generate `TRUNCATE` statements only after enumerating approved application schemas and excluding system schemas. Foreign-key ordering and `FOREIGN_KEY_CHECKS` behavior must be tested; a schema-only restore remains preferred.

### Phase 6 — validation

Required gates:

- Expected schema count and schema checksum.
- Every manifest table classified and action completed.
- Required migration/config tables populated.
- Truncated tables have exact row count zero.
- Retained/subset tables meet approved row-count and date-boundary checks.
- No prohibited customer-data patterns remain in sampled validation queries.
- Application smoke tests pass against the temporary endpoint.
- Cluster instance class, backup retention, deletion protection, logging, and tags match development policy.
- Estimated `VolumeBytesUsed` and table logical size are recorded as post-refresh baselines.

Validation must not print sampled sensitive values.

### Phase 7 — cutover and rollback

1. Require approval after validation.
2. Update the development secret, DNS alias, or application configuration pointer to the new endpoint.
3. Restart or redeploy development services if connection pools cache DNS or credentials.
4. Run post-cutover smoke tests.
5. Keep the previous development cluster for a short, explicitly costed rollback window.
6. Delete the previous cluster and obsolete final snapshot only after approval.
7. Emit a final report with cluster IDs, manifest version, validations, storage size, elapsed time, and cleanup status.

## IAM outline

The CodeBuild role should have narrowly scoped permissions for:

- `sts:GetCallerIdentity`
- Read source RDS cluster/snapshot metadata
- Create, tag, describe, and delete only `piqdev-refresh-*` resources
- Create only approved development instance classes
- Use the approved KMS key
- Read/write designated target Secrets Manager secrets
- Write CloudWatch Logs and refresh metrics
- Publish completion/failure notifications

Use explicit denies or permission boundaries for production modification/deletion. Scope resources by ARN and request/resource tags wherever supported.

## Network and credential requirements

- Run CodeBuild in approved private subnets with security-group access to the temporary target.
- Do not make the refreshed database publicly accessible.
- Use TLS for MySQL.
- Store runtime credentials in Secrets Manager.
- Disable shell tracing around secret retrieval.
- Pipe secrets directly to the client process; do not write them to workspace files.
- Use separate source-read and target-admin credentials.

## Observability

Record per refresh:

- Build ID and approval/change ticket
- Source and target cluster ARNs
- Source-copy method
- Engine versions
- Manifest version and checksum
- Per-action duration and outcome
- Pre/post logical table sizes
- Pre/post `VolumeBytesUsed`
- Snapshot and old-cluster cleanup status
- Cutover and rollback timestamps

Create alarms or notifications for failed refreshes, partial sanitization, cleanup failures, and targets that outlive the rollback window.

## Failure handling

- Failure before cutover: delete the temporary target after preserving diagnostic metadata.
- Failure during sanitization: never cut over; resume only if the manifest actions are idempotent, otherwise recreate the target.
- Failure after cutover: restore the previous development pointer during the rollback window.
- Cleanup failure: alert and track the temporary/old cluster as a cost leak.
- Any safety-check failure: stop without attempting recovery SQL.

## Acceptance criteria for implementation

1. A dry-run mode performs all discovery, classification, and safety checks without creating or changing resources.
2. Production cannot be modified even if build parameters are malicious or incorrect.
3. A refresh can be rerun or resumed without duplicate targets or ambiguous state.
4. All table actions come from a reviewed manifest.
5. Sensitive values do not appear in CodeBuild logs or artifacts.
6. Validation proves the new development database meets the selected schema-only or curated-copy policy.
7. Previous clusters and snapshots are cleaned up after the rollback window.
8. The final report includes cost/storage deltas.

## Open decisions

- Does development need schema only, or selected production-derived data?
- Which lookup/configuration tables must remain populated?
- Which user, reservation, and telemetry data is needed for tests?
- Required retention cutoffs for power, heart-rate, and rower series.
- Whether Aurora clone or snapshot restore behaves better after PIQ's truncation/rebuild workload.
- Required redaction rules and privacy approval.
- Cutover mechanism: Secrets Manager endpoint, DNS alias, or application configuration.
- Rollback window length and acceptable temporary double-running cost.
- Whether Step Functions should orchestrate the RDS lifecycle around CodeBuild.

## AWS references

- [Cloning an Aurora cluster volume](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Clone.html)
- [Aurora snapshot copying](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-copy-snapshot.html)
- [Understanding Aurora backup storage usage](https://docs.aws.amazon.com/en_us/AmazonRDS/latest/AuroraUserGuide/aurora-storage-backup.html)
