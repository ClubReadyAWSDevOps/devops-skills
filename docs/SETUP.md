# GitHub Actions IAM Setup for AWS Audits

This guide walks through setting up IAM permissions for the automated AWS audit workflow.

## Overview

The GitHub Actions workflow (`monthly-aws-audit.yml`) uses OIDC to authenticate to AWS and run read-only audits across multiple accounts. It also invokes Claude via AWS Bedrock for analysis.

## Prerequisites

- Existing `github-actions-claude-review` IAM role with OIDC trust policy
- AWS CLI configured with admin permissions
- Multiple AWS accounts to audit (optional)

## Quick Setup

Run the automated setup script:

```bash
cd ~/projects/devops-skills
./scripts/setup-iam-role-permissions.sh
```

This script will:
1. Verify the `github-actions-claude-review` role exists
2. Validate the IAM policy JSON
3. Apply the policy to the role
4. Display a verification summary

## Manual Setup

If you prefer to set up manually or need a dedicated audit role:

### 1. Create IAM Policy

```bash
aws iam put-role-policy --region us-west-2 \
  --role-name github-actions-claude-review \
  --policy-name GitHubActionsAuditAndBedrock \
  --policy-document file://docs/iam-policy-github-actions.json
```

### 2. Verify Policy

```bash
aws iam get-role-policy --region us-west-2 \
  --role-name github-actions-claude-review \
  --policy-name GitHubActionsAuditAndBedrock
```

## Policy Permissions

The `iam-policy-github-actions.json` policy includes:

### Bedrock (AI/ML)
- `bedrock:InvokeModel` — Run Claude models
- `bedrock:InvokeModelWithResponseStream` — Streaming responses

### Cost Management
- Cost Explorer: `ce:GetCostAndUsage`, `ce:GetReservationUtilization`, etc.
- Budgets: `budgets:DescribeBudgets`, `budgets:ViewBudget`

### IAM Security Audit
- `iam:GenerateCredentialReport` — Create credential report
- `iam:GetCredentialReport` — Read credential report
- `iam:ListUsers`, `iam:ListAccessKeys`, `iam:ListMFADevices` — User audit

### Infrastructure Read-Only
- **Compute:** EC2, ECS, Lambda (Describe*, List*)
- **Database:** RDS, DynamoDB, ElastiCache (Describe*, List*)
- **Storage:** S3 (GetBucket*, ListAllMyBuckets)
- **Networking:** ELB, CloudFront (Describe*, List*)
- **Monitoring:** CloudWatch, CloudWatch Logs (Describe*, Get*, List*)
- **Secrets:** Secrets Manager (ListSecrets, DescribeSecret — no GetSecretValue)

### Multi-Account
- **Organizations:** Describe organization, list accounts, list OUs
- **IAM Identity Center:** List instances, permission sets, account assignments

### Identity
- `sts:GetCallerIdentity` — Verify authentication

## Multi-Account Setup

To audit multiple AWS accounts:

### 1. Add GitHub Secret

In each repository that runs audits:

```
Name: AWS_ACCOUNT_IDS
Value: 123456789012,234567890123,345678901234
```

Comma-separated list of AWS account IDs.

### 2. Create Role in Each Account

For **each AWS account** you want to audit, create the same IAM role:

```bash
# In each target account
aws iam create-role --region us-west-2 \
  --role-name github-actions-claude-review \
  --assume-role-policy-document file://oidc-trust-policy.json

aws iam put-role-policy --region us-west-2 \
  --role-name github-actions-claude-review \
  --policy-name GitHubActionsAuditAndBedrock \
  --policy-document file://docs/iam-policy-github-actions.json
```

**OIDC Trust Policy** (`oidc-trust-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ClubReadyAWSDevOps/devops-skills:*"
        }
      }
    }
  ]
}
```

Replace `<ACCOUNT_ID>` with the target account ID.

### 3. Verify Setup

```bash
# Test OIDC authentication (run from GitHub Actions or manually with token)
aws sts get-caller-identity --region us-west-2
```

## Security Considerations

### Read-Only Access

All permissions are **read-only** — no write, delete, or modify actions:
- ✅ `Describe*`, `List*`, `Get*`
- ❌ `Create*`, `Delete*`, `Update*`, `Put*`

**Exception:** `iam:GenerateCredentialReport` (required for credential audit, read-only output)

### Bedrock Access

Bedrock permissions are scoped to:
- **Claude models only:** `anthropic.claude-*`
- **Titan models** (if needed for embeddings)
- **No custom models** or fine-tuned variants

### No Secrets Access

The policy does **NOT** include:
- `secretsmanager:GetSecretValue` — Cannot read secret values
- `ssm:GetParameter` — Cannot read SSM parameters
- `rds:DownloadDBLogFilePortion` — Cannot read DB logs with sensitive data

Audits verify secrets **exist** and **rotation is enabled**, but never read the values.

### Least Privilege

If you don't need certain services, remove them from the policy:

```bash
# Example: Remove Organizations access if not using multi-account
jq 'del(.Statement[] | select(.Sid == "OrganizationsReadOnly"))' docs/iam-policy-github-actions.json > custom-policy.json
```

## Troubleshooting

### Error: "Role does not exist"

Create the role first:
```bash
aws iam create-role --role-name github-actions-claude-review \
  --assume-role-policy-document file://oidc-trust-policy.json
```

### Error: "Access denied" during audit

Check that the role has the required permissions:
```bash
aws iam get-role-policy --role-name github-actions-claude-review \
  --policy-name GitHubActionsAuditAndBedrock
```

### Bedrock "Model not found"

Ensure Bedrock model access is enabled in the AWS account:
```bash
aws bedrock list-foundation-models --region us-west-2 \
  --query 'modelSummaries[?contains(modelId, `claude`)]'
```

If no models returned, enable access via AWS Console:
- Bedrock → Model access → Request access to Claude models

### Multiple accounts not working

Verify:
1. `AWS_ACCOUNT_IDS` secret is set correctly (comma-separated, no spaces)
2. Each account has the `github-actions-claude-review` role
3. OIDC provider exists in each account: `token.actions.githubusercontent.com`

## Cost Estimation

Running the audit workflow:
- **AWS API calls:** ~100-200 read-only calls per account (free tier)
- **Bedrock Claude invocations:** ~5-10 requests per audit (~$0.50/account/month)
- **GitHub Actions minutes:** ~10 minutes per account (free tier: 2,000 min/month)

**Total cost:** < $1/month for 3 accounts

## References

- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Bedrock IAM Permissions](https://docs.aws.amazon.com/bedrock/latest/userguide/security-iam.html)
- [Cost Explorer API](https://docs.aws.amazon.com/cost-management/latest/APIReference/Welcome.html)
