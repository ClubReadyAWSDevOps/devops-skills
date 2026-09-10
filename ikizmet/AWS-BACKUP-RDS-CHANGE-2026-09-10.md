# AWS Backup RDS Exclusion — 2026-09-10

Status: completed and verified  
AWS account: `410878187014` (`sa-ikizmet`)  
Region: `us-west-2`  
Service affected: AWS Backup resource selection only

## Intent

Stop creating new AWS Backup recovery points for iKizmet RDS and Aurora resources because native RDS automated backups are enabled. Preserve all existing AWS Backup recovery points until normal lifecycle expiration, preserve native backups, and preserve the shared selection behavior for non-RDS resources.

## Approval

The user explicitly confirmed both the intended RDS exclusion and, after discovering that AWS Backup selections are immutable, the safe create-verify-delete replacement procedure.

No recovery point deletion, native retention change, or database operation was authorized.

## Pre-change state

AWS Backup plan:

- Name: `Backup-Production-Plan`
- Plan ID: `384c6e01-42b3-4c89-8d33-6369d6ee4cb7`
- Rule schedule: `cron(30 0 ? * * *)`
- Schedule timezone: `Europe/Warsaw`
- Target vault: `iKizmet-Production-Vault`
- Recovery-point lifecycle: delete after 30 days

Original selection:

- Name: `Backup-Assignement`
- Selection ID: `71c6e35b-d451-46f6-bf0d-a663dde88600`
- Resources: `*`
- Condition: `aws:ResourceTag/Backup = true`
- Exclusions: none

It selected these five Oregon Aurora clusters:

- `app`
- `app-anatomy`
- `app-demo-cluster`
- `app-qa`
- `app-xpo`

The vault contained 150 Aurora recovery points, 30 per cluster. Standalone `quicksight` was not producing AWS Backup recovery points.

Native retention before the change:

| Resource | Native retention |
|---|---:|
| `app` | 30 days |
| `app-anatomy` | 30 days |
| `app-demo-cluster` | 30 days |
| `app-xpo` | 30 days |
| Oregon `app-qa` | 7 days |
| Frankfurt `app-qa-cluster` | 7 days |
| Standalone `quicksight` | 30 days |

## Executed change

AWS Backup does not expose an update operation for an existing backup selection. An initial attempted `update-backup-selection` command was rejected by the local AWS CLI before contacting AWS, so it made no state change.

A fail-safe replacement was then performed:

1. Created `Backup-Assignment-No-RDS` while the original selection remained active.
2. Read the new selection back and programmatically verified every relevant field.
3. Deleted the original selection only after all checks passed.

Replacement selection:

- Name: `Backup-Assignment-No-RDS`
- Selection ID: `dba1141b-6c72-4b9b-bac9-dd960c4af37c`
- IAM role: unchanged AWS Backup default service role
- Resources: `*`
- Condition: `aws:ResourceTag/Backup = true`
- Other conditions: empty
- Exclusions:

```text
arn:aws:rds:us-west-2:410878187014:cluster:*
arn:aws:rds:us-west-2:410878187014:db:*
```

The exclusions cover current and future Aurora clusters and standalone RDS DB instances in this account and region. They do not remove the `Backup=true` tags and do not change selection behavior for non-RDS resources.

## Post-change verification

All checks passed immediately after replacement:

- Exactly one backup selection remains in the plan.
- Its ID is `dba1141b-6c72-4b9b-bac9-dd960c4af37c`.
- `Resources=["*"]` is preserved.
- The `Backup=true` condition is preserved.
- The IAM role is preserved.
- The only `NotResources` entries are the two approved RDS patterns.
- The plan schedule, timezone, vault, and 30-day lifecycle are unchanged.
- All RDS/Aurora resources report `available`.
- Native retention periods are unchanged.
- Native automated snapshots dated 2026-09-10 were `available` for all five Oregon Aurora clusters, Frankfurt QA, and standalone `quicksight`.
- The vault still contains all 150 existing Aurora recovery points; no recovery point was deleted.

## Current behavior

- Future AWS Backup jobs from this plan will not select Oregon RDS DB instances or Aurora clusters.
- Native RDS automated backups continue according to each resource's retention period.
- Existing AWS Backup recovery points remain restorable and will age out under their existing 30-day lifecycle.
- Backup-cost reduction will be gradual rather than immediate.
- Manual snapshots, the legacy-vault recovery point, Frankfurt native backups, and all database data are unchanged.

The actual cost decrease cannot be equated directly to the full August `$1,558.82` Aurora backup charge because existing points remain temporarily, native backup billing continues, and Aurora backup storage is incremental.

## Rollback

If AWS Backup RDS coverage must be restored, use the same no-gap pattern:

1. Create a new selection with the same role, `Resources=["*"]`, and `Backup=true` condition but no RDS exclusions.
2. Read it back and verify all fields.
3. Delete `Backup-Assignment-No-RDS` only after verification.
4. Confirm the next scheduled job creates expected RDS/Aurora recovery points.

Do not delete and recreate the current selection in the opposite order, because that would create an avoidable backup-selection gap.

## Follow-up

- After the next scheduled run, verify no new RDS/Aurora AWS Backup job or recovery point was created.
- Monitor the vault count and Aurora backup cost as the existing 30-day recovery points expire.
- Keep native automated-backup alarms and restore testing in place.
- Continue the separate ownership review for manual snapshots and the legacy-vault recovery point.
