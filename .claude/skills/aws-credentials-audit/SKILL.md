---
name: aws-credentials-audit
description: Audit AWS credentials security — unused access keys, old passwords, MFA compliance, expired certs, and rotation hygiene. Use for quarterly security reviews or incident response.
---

## AWS Credentials Security Audit

Comprehensive audit of IAM users, access keys, passwords, MFA status, and credential rotation compliance.

### Prerequisites

- AWS CLI with IAM read permissions (`iam:Get*`, `iam:List*`)
- `jq` for JSON parsing
- Credential Report generated within last 4 hours (auto-generated if stale)

### Workflow

1. **Generate IAM Credential Report** (if not recent)
   ```bash
   aws iam generate-credential-report --region us-west-2
   # Wait ~10 seconds for report generation
   sleep 10
   aws iam get-credential-report --region us-west-2 --query 'Content' --output text | base64 --decode > /tmp/iam-creds.csv
   ```

2. **Find IAM users with access keys unused >90 days**
   ```bash
   awk -F, 'NR>1 && $11 != "N/A" && $11 != "no_information" {
     cmd = "date -d \""$11"\" +%s 2>/dev/null || date -j -f \"%Y-%m-%dT%H:%M:%S%z\" \""$11"\" +%s 2>/dev/null"
     cmd | getline last_used
     close(cmd)
     
     cmd2 = "date +%s"
     cmd2 | getline now
     close(cmd2)
     
     days = (now - last_used) / 86400
     if (days > 90) {
       printf "%s: Key1 unused for %d days (last used: %s)\n", $1, days, $11
     }
   }' /tmp/iam-creds.csv
   
   # Repeat for access_key_2 (column 16)
   ```

3. **Find users with passwords but no MFA enabled**
   ```bash
   awk -F, 'NR>1 && $4 == "true" && $8 == "false" {
     printf "❌ %s: Password enabled but MFA disabled (created: %s)\n", $1, $3
   }' /tmp/iam-creds.csv
   ```

4. **Find access keys older than 90 days (rotation policy)**
   ```bash
   awk -F, 'NR>1 && $9 != "N/A" && $9 != "false" {
     cmd = "date -d \""$9"\" +%s 2>/dev/null || date -j -f \"%Y-%m-%dT%H:%M:%S%z\" \""$9"\" +%s 2>/dev/null"
     cmd | getline created
     close(cmd)
     
     cmd2 = "date +%s"
     cmd2 | getline now
     close(cmd2)
     
     days = (now - created) / 86400
     if (days > 90) {
       printf "⚠️  %s: Key1 is %d days old (created: %s) — rotate soon\n", $1, days, $9
     }
   }' /tmp/iam-creds.csv
   ```

5. **Find users with password last changed >180 days ago**
   ```bash
   awk -F, 'NR>1 && $5 != "N/A" && $5 != "not_supported" && $5 != "no_information" {
     cmd = "date -d \""$5"\" +%s 2>/dev/null || date -j -f \"%Y-%m-%dT%H:%M:%S%z\" \""$5"\" +%s 2>/dev/null"
     cmd | getline changed
     close(cmd)
     
     cmd2 = "date +%s"
     cmd2 | getline now
     close(cmd2)
     
     days = (now - changed) / 86400
     if (days > 180) {
       printf "🔴 %s: Password %d days old — force rotation\n", $1, days
     }
   }' /tmp/iam-creds.csv
   ```

6. **Check Secrets Manager secrets rotation status**
   ```bash
   aws secretsmanager list-secrets --region us-west-2 | jq -r '.SecretList[] | select(.RotationEnabled == false) | "❌ \(.Name): Rotation disabled"'
   
   # Check last rotation date for enabled secrets
   aws secretsmanager list-secrets --region us-west-2 | jq -r '.SecretList[] | select(.RotationEnabled == true) | "✅ \(.Name): Last rotated \(.LastRotatedDate // "never")"'
   ```

7. **Find IAM roles with inline policies (anti-pattern)**
   ```bash
   aws iam list-roles --region us-west-2 --query 'Roles[*].RoleName' --output text | while read role; do
     INLINE_COUNT=$(aws iam list-role-policies --region us-west-2 --role-name "$role" --query 'length(PolicyNames)' --output text)
     if [ "$INLINE_COUNT" -gt 0 ]; then
       echo "⚠️  $role: Has $INLINE_COUNT inline policies (use managed policies instead)"
     fi
   done
   ```

8. **Check for overly permissive policies (AdministratorAccess outside approved roles)**
   ```bash
   aws iam list-entities-for-policy --region us-west-2 --policy-arn arn:aws:iam::aws:policy/AdministratorAccess | jq -r '.PolicyUsers[] | "🔴 User: \(.UserName)"'
   aws iam list-entities-for-policy --region us-west-2 --policy-arn arn:aws:iam::aws:policy/AdministratorAccess | jq -r '.PolicyRoles[] | select(.RoleName | startswith("Admin") or startswith("CloudInfra") | not) | "⚠️  Role: \(.RoleName) (review if needed)"'
   ```

9. **Find unused IAM users (no activity in 90 days)**
   ```bash
   awk -F, 'NR>1 {
     # Check password_last_used (col 5) and access_key_1_last_used_date (col 11)
     pw = $5; key = $11
     
     if ((pw == "N/A" || pw == "no_information") && (key == "N/A" || key == "no_information")) {
       printf "🗑️  %s: No activity recorded (created: %s) — candidate for deletion\n", $1, $3
     }
   }' /tmp/iam-creds.csv
   ```

10. **Check for root account usage (critical alert)**
    ```bash
    aws iam get-account-summary --region us-west-2 | jq -r 'if .SummaryMap.AccountMFAEnabled == 1 then "✅ Root MFA enabled" else "🔴 ROOT MFA DISABLED — CRITICAL RISK" end'
    
    # Check root access key existence (should never exist)
    aws iam get-account-summary --region us-west-2 | jq -r 'if .SummaryMap.AccountAccessKeysPresent == 0 then "✅ No root access keys" else "🔴 ROOT ACCESS KEYS EXIST — DELETE IMMEDIATELY" end'
    ```

### Output Format

```
=== AWS Credentials Security Audit: 2026-06-24 ===

🔴 CRITICAL ISSUES:
- Root MFA: ❌ DISABLED (enable immediately)
- Root Access Keys: ✅ None (good)

Users Without MFA (4):
❌ dev-user-1: Password enabled, no MFA (created 2025-03-15)
❌ ci-deploy: Access keys only, no MFA (created 2024-11-20)
❌ contractor-jane: Password enabled, no MFA (created 2026-01-10)
❌ legacy-sync: Access keys, no MFA (created 2023-08-05)

Unused Access Keys >90 days (3):
⚠️  backup-script: Key unused for 127 days (last used 2026-02-17)
⚠️  analytics-reader: Key unused for 201 days (last used 2025-12-05)
🗑️  old-migration-user: Key unused for 487 days — DELETE

Access Keys Needing Rotation >90 days (5):
⚠️  rds-backup-user: Key is 143 days old (created 2026-02-01)
⚠️  s3-sync-prod: Key is 267 days old (created 2025-10-01)
🔴 glue-etl-user: Key is 512 days old (created 2025-01-27) — OVERDUE

Old Passwords >180 days (2):
🔴 admin-john: Password 223 days old — force rotation
🔴 contractor-jane: Password 195 days old — force rotation

Secrets Manager (8 secrets):
✅ rds/app-prod: Rotated 2026-06-15 (9 days ago)
✅ rds/app-qa: Rotated 2026-06-10 (14 days ago)
❌ legacy/mssql-password: Rotation DISABLED (created 2024-03-20)
❌ stripe/api-key: Rotation DISABLED (created 2025-11-12)

Inline Policies (anti-pattern):
⚠️  legacy-lambda-role: 2 inline policies (migrate to managed)
⚠️  data-pipeline-role: 1 inline policy (migrate to managed)

Overly Permissive Access:
🔴 User analytics-admin: Has AdministratorAccess (review necessity)
⚠️  Role LambdaExecutionRole: Has AdministratorAccess (scope down)

Unused Users (candidates for deletion):
🗑️  temp-contractor-2025: No activity, created 2025-09-10
🗑️  poc-test-user: No activity, created 2024-12-15

=== Summary ===
🔴 Critical: 1 (Root MFA disabled)
⚠️  High: 11 (old keys, no MFA, inline policies)
ℹ️  Medium: 8 (unused keys, rotation upcoming)

Action Items:
1. Enable root account MFA immediately
2. Rotate 3 overdue access keys (>1 year old)
3. Force password reset for 2 users (>180 days)
4. Enable MFA for 4 users without it
5. Delete 3 unused users (no activity >1 year)
6. Enable rotation for 2 Secrets Manager secrets
```

### Remediation Commands

**Delete unused access key:**
```bash
aws iam delete-access-key --region us-west-2 --user-name <username> --access-key-id <AKIAXXXXXXXX>
```

**Rotate access key:**
```bash
# Create new key
aws iam create-access-key --region us-west-2 --user-name <username>
# Update application config with new key
# Test new key works
# Delete old key
aws iam delete-access-key --region us-west-2 --user-name <username> --access-key-id <old-key-id>
```

**Enable MFA for user (requires console):**
```bash
# Must be done via AWS Console or authenticated with user's credentials
# https://console.aws.amazon.com/iam → Users → <user> → Security credentials → Assign MFA
```

**Delete unused user:**
```bash
# First, list and delete attached policies/groups
aws iam list-user-policies --region us-west-2 --user-name <username>
aws iam list-attached-user-policies --region us-west-2 --user-name <username>
aws iam delete-user --region us-west-2 --user-name <username>
```

### Integration

- Run **quarterly** as part of security compliance audit
- Run **immediately** after employee offboarding
- Run before security audits or SOC 2 reviews
- Integrate with `/aws-iam-permissions-audit` for full IAM posture review

### Notes

- Credential report is cached for 4 hours — regenerate for fresh data
- Access key last-used date updated within 4 hours (not real-time)
- Service accounts (CI/CD) should use IAM roles, not access keys when possible
- Consider AWS SSO / Identity Center for human users instead of IAM users
