# Quick Start: AWS Multi-Account Audit Setup

Complete setup in 5 minutes per account.

## Prerequisites

- [x] AWS CLI installed and configured
- [x] Admin permissions in target AWS accounts
- [x] GitHub CLI (`gh`) authenticated
- [x] This repository cloned: `~/projects/devops-skills`

## Step-by-Step Setup

### Step 1: Run Setup Script in Each AWS Account

```bash
cd ~/projects/devops-skills

# Switch to first account (e.g., Production)
export AWS_PROFILE=production  # or use aws-vault, aws sso login, etc.

# Run complete setup (OIDC provider + role + permissions)
./scripts/setup-iam-role-complete.sh
```

**What it does:**
- ✅ Creates GitHub OIDC provider (if missing)
- ✅ Creates `github-actions-claude-review` IAM role
- ✅ Configures trust policy for your GitHub repository
- ✅ Applies audit + Bedrock permissions
- ✅ Verifies setup

**Repeat for each account:**
```bash
# Staging account
export AWS_PROFILE=staging
./scripts/setup-iam-role-complete.sh

# Development account
export AWS_PROFILE=development
./scripts/setup-iam-role-complete.sh
```

---

### Step 2: Add Account IDs to GitHub

Already done! You added:
```
AWS_ACCOUNT_IDS=<account1>,<account2>,<account3>
```

---

### Step 3: Test the Workflow

**Option A: Manual trigger (recommended for first run)**
```bash
gh workflow run monthly-aws-audit.yml --repo ClubReadyAWSDevOps/devops-skills

# Watch progress
gh run watch --repo ClubReadyAWSDevOps/devops-skills
```

**Option B: Wait for scheduled run**
- Runs automatically on 1st of each month at 9 AM UTC

---

### Step 4: Review GitHub Issues

After ~5-10 minutes, check for issues:

```bash
gh issue list --repo ClubReadyAWSDevOps/devops-skills --label aws-audit
```

You'll see one issue per account:
- `AWS Audit: Production (123456789012) — 2026-06-24`
- `AWS Audit: Staging (234567890123) — 2026-06-24`
- `AWS Audit: Development (345678901234) — 2026-06-24`

Each issue includes:
- Executive summary (cost, security, architecture scores)
- Priority findings (P0-P3)
- Detailed audit outputs
- **Missing permissions** (if any — apply and re-run)

---

## Troubleshooting

### "Role already exists"
```bash
# Update permissions only
./scripts/setup-iam-role-permissions.sh
```

### "OIDC provider already exists"
The script handles this automatically — it will reuse the existing provider.

### "AccessDenied" during audit
Check the GitHub issue — it will show missing permissions with a ready-to-apply policy. Then:
```bash
# Extract missing permissions JSON from issue, save to file
./scripts/add-missing-permissions.sh missing-perms.json

# Re-run audit
gh workflow run monthly-aws-audit.yml --repo ClubReadyAWSDevOps/devops-skills
```

### Workflow not running
Verify GitHub secret is set:
```bash
gh secret list --repo ClubReadyAWSDevOps/devops-skills | grep AWS_ACCOUNT_IDS
```

---

## One-Command Setup (All Accounts)

If you have AWS profiles configured for each account:

```bash
cd ~/projects/devops-skills

for profile in production staging development; do
  echo "Setting up account: $profile"
  AWS_PROFILE=$profile ./scripts/setup-iam-role-complete.sh
  echo ""
done
```

---

## What Happens on Each Audit Run

```
┌─────────────────────────────────────────────┐
│  GitHub Actions triggers monthly-aws-audit  │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────┴───────────┬──────────────────┐
        ▼                      ▼                  ▼
   Production              Staging          Development
   (123456789)            (234567890)       (345678901)
        │                      │                  │
        ├─ OIDC Auth           ├─ OIDC Auth       ├─ OIDC Auth
        ├─ Cost Review         ├─ Cost Review     ├─ Cost Review
        ├─ Credentials Audit   ├─ Creds Audit     ├─ Creds Audit
        ├─ Architecture Review ├─ Arch Review     ├─ Arch Review
        ├─ Reserved Capacity   ├─ Reserved Cap    ├─ Reserved Cap
        ├─ Consolidate         ├─ Consolidate     ├─ Consolidate
        └─ Create Issue #123   └─ Create Issue    └─ Create Issue
                                  #124                #125
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `setup-iam-role-complete.sh` | **Run this first** — Creates role + permissions |
| `setup-iam-role-permissions.sh` | Update permissions only (if role exists) |
| `add-missing-permissions.sh` | Add permissions detected during audits |
| `.github/workflows/monthly-aws-audit.yml` | GitHub Actions workflow definition |
| `docs/iam-policy-github-actions.json` | IAM policy with all required permissions |

---

## Cost Estimate

Per account, per month:
- AWS API calls: $0 (read-only, free tier)
- Bedrock (Claude): ~$0.50 (5-10 invocations)
- GitHub Actions: $0 (free tier: 2,000 min/month)

**Total: ~$0.50/account/month** or **$1.50/month for 3 accounts**

---

## Next Steps After First Run

1. **Review P0 (Critical) findings** → Fix within 24 hours
2. **Assign owners to P1 (High) items** → Fix this week
3. **Add any missing permissions** → Run add-missing-permissions.sh
4. **Set up Slack notifications** (optional) — Add webhook to workflow

---

## Support

- **Setup issues:** Check `docs/SETUP.md` for detailed guide
- **Workflow failures:** View logs: `gh run view --repo ClubReadyAWSDevOps/devops-skills`
- **Permission errors:** Check GitHub issue for auto-detected missing permissions
- **Questions:** Create issue: `gh issue create --repo ClubReadyAWSDevOps/devops-skills`
