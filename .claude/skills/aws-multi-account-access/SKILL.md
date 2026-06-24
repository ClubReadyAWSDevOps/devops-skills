---
name: aws-multi-account-access
description: Configure cross-account access for AWS Organizations with IAM Identity Center (SSO) or assume-role patterns. Use when adding new AWS accounts or setting up centralized access management.
---

## AWS Multi-Account Access Setup

Configure secure, scalable cross-account access for AWS Organizations using IAM Identity Center (formerly AWS SSO) for human users and IAM assume-role for service-to-service access.

### Architecture Options

**Option A: IAM Identity Center (Recommended for Human Users)**
```
Management Account
  → IAM Identity Center
    → Permission Sets (AdministratorAccess, ReadOnly, etc.)
      → Account Assignments
        → Production Account (123456789012)
        → Staging Account (234567890123)
        → Development Account (345678901234)
```

**Option B: Cross-Account IAM Roles (Service Accounts & CI/CD)**
```
Source Account (CI/CD, Lambda, ECS)
  → Assume IAM Role
    → Target Account
      → Scoped Permissions (RDS, S3, ECS)
```

---

## Part 1: AWS Organizations Setup

### 1. Create AWS Organization (Management Account)

```bash
# Run from the account that will be the management account
aws organizations create-organization --region us-west-2 --feature-set ALL

# Verify creation
aws organizations describe-organization --region us-west-2 | jq -r '.Organization | {Id, MasterAccountId, FeatureSet}'
```

### 2. Create Organizational Units (OUs)

```bash
ROOT_ID=$(aws organizations list-roots --region us-west-2 --query 'Roots[0].Id' --output text)

# Production OU
aws organizations create-organizational-unit --region us-west-2 --parent-id "$ROOT_ID" --name Production

# Non-Production OU
aws organizations create-organizational-unit --region us-west-2 --parent-id "$ROOT_ID" --name NonProduction

# Sandbox OU (for experimentation)
aws organizations create-organizational-unit --region us-west-2 --parent-id "$ROOT_ID" --name Sandbox
```

### 3. Create Member Accounts

```bash
# Production account
aws organizations create-account --region us-west-2 --email aws-prod@clubready.com --account-name "ClubReady Production" --role-name OrganizationAccountAccessRole

# Staging account
aws organizations create-account --region us-west-2 --email aws-staging@clubready.com --account-name "ClubReady Staging" --role-name OrganizationAccountAccessRole

# Wait for account creation (async operation)
aws organizations list-accounts --region us-west-2 | jq -r '.Accounts[] | select(.Status == "ACTIVE") | {Id, Name, Email}'
```

### 4. Move Accounts to OUs

```bash
PROD_OU_ID=$(aws organizations list-organizational-units-for-parent --region us-west-2 --parent-id "$ROOT_ID" --query 'OrganizationalUnits[?Name==`Production`].Id' --output text)

PROD_ACCOUNT_ID=123456789012  # Replace with actual ID from step 3

aws organizations move-account --region us-west-2 --account-id "$PROD_ACCOUNT_ID" --source-parent-id "$ROOT_ID" --destination-parent-id "$PROD_OU_ID"
```

---

## Part 2: IAM Identity Center (SSO) Setup

### 1. Enable IAM Identity Center

```bash
# Must be done via AWS Console (one-time setup)
# https://console.aws.amazon.com/singlesignon
# Region: us-west-2 (or your preferred SSO region)
# Choose identity source: Identity Center directory (default) or Active Directory

# After setup, get SSO instance ARN
aws sso-admin list-instances --region us-west-2 | jq -r '.Instances[0] | {InstanceArn, IdentityStoreId}'
```

### 2. Create Permission Sets

**AdministratorAccess Permission Set:**
```bash
SSO_INSTANCE_ARN=$(aws sso-admin list-instances --region us-west-2 --query 'Instances[0].InstanceArn' --output text)

aws sso-admin create-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --name AdministratorAccess --description "Full administrator access" --session-duration PT2H

ADMIN_PS_ARN=$(aws sso-admin list-permission-sets --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --query 'PermissionSets[0]' --output text)

# Attach AWS managed policy
aws sso-admin attach-managed-policy-to-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --permission-set-arn "$ADMIN_PS_ARN" --managed-policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**ReadOnlyAccess Permission Set:**
```bash
aws sso-admin create-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --name ReadOnlyAccess --description "Read-only access" --session-duration PT8H

READONLY_PS_ARN=$(aws sso-admin list-permission-sets --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --query 'PermissionSets[1]' --output text)

aws sso-admin attach-managed-policy-to-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --permission-set-arn "$READONLY_PS_ARN" --managed-policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

**Custom Permission Set (e.g., Developer):**
```bash
aws sso-admin create-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --name DeveloperAccess --description "ECS, RDS, S3, CloudWatch access" --session-duration PT4H

DEV_PS_ARN=$(aws sso-admin list-permission-sets --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --query 'PermissionSets[2]' --output text)

# Create inline policy
cat > /tmp/developer-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "rds:Describe*",
        "rds:ListTagsForResource",
        "s3:ListBucket",
        "s3:GetObject",
        "logs:*",
        "cloudwatch:*",
        "ec2:Describe*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Action": [
        "rds:DeleteDBInstance",
        "rds:DeleteDBCluster",
        "s3:DeleteBucket"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws sso-admin put-inline-policy-to-permission-set --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --permission-set-arn "$DEV_PS_ARN" --inline-policy file:///tmp/developer-policy.json
```

### 3. Create Users and Groups

```bash
IDENTITY_STORE_ID=$(aws sso-admin list-instances --region us-west-2 --query 'Instances[0].IdentityStoreId' --output text)

# Create group
aws identitystore create-group --region us-west-2 --identity-store-id "$IDENTITY_STORE_ID" --display-name CloudInfraTeam --description "Cloud Infrastructure Team"

CLOUD_INFRA_GROUP_ID=$(aws identitystore list-groups --region us-west-2 --identity-store-id "$IDENTITY_STORE_ID" --query 'Groups[?DisplayName==`CloudInfraTeam`].GroupId' --output text)

# Create user
aws identitystore create-user --region us-west-2 --identity-store-id "$IDENTITY_STORE_ID" --user-name john.doe --display-name "John Doe" --name FamilyName=Doe,GivenName=John --emails Value=john.doe@clubready.com,Primary=true

USER_ID=$(aws identitystore list-users --region us-west-2 --identity-store-id "$IDENTITY_STORE_ID" --query 'Users[?UserName==`john.doe`].UserId' --output text)

# Add user to group
aws identitystore create-group-membership --region us-west-2 --identity-store-id "$IDENTITY_STORE_ID" --group-id "$CLOUD_INFRA_GROUP_ID" --member-id UserId="$USER_ID"
```

### 4. Assign Permission Sets to Accounts

```bash
# Assign AdministratorAccess to CloudInfraTeam in Production account
aws sso-admin create-account-assignment --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --permission-set-arn "$ADMIN_PS_ARN" --principal-type GROUP --principal-id "$CLOUD_INFRA_GROUP_ID" --target-type AWS_ACCOUNT --target-id 123456789012

# Assign ReadOnlyAccess to john.doe in Staging account
aws sso-admin create-account-assignment --region us-west-2 --instance-arn "$SSO_INSTANCE_ARN" --permission-set-arn "$READONLY_PS_ARN" --principal-type USER --principal-id "$USER_ID" --target-type AWS_ACCOUNT --target-id 234567890123
```

---

## Part 3: Cross-Account IAM Roles (Service Access)

### 1. Create Assume Role in Target Account

**In Target Account (e.g., Production 123456789012):**

**trust-policy.json:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::999888777666:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id-12345"
        }
      }
    }
  ]
}
```

```bash
aws iam create-role --region us-west-2 --role-name CrossAccountAccessFromCI --assume-role-policy-document file://trust-policy.json --description "Allow CI/CD from central account"

# Attach permissions
aws iam attach-role-policy --region us-west-2 --role-name CrossAccountAccessFromCI --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

### 2. Grant Assume Permission in Source Account

**In Source Account (999888777666):**

**assume-policy.json:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::123456789012:role/CrossAccountAccessFromCI"
    }
  ]
}
```

```bash
aws iam put-user-policy --region us-west-2 --user-name ci-deploy --policy-name AssumeProductionRole --policy-document file://assume-policy.json
```

### 3. Assume Role from Source Account

```bash
# As ci-deploy user in source account
aws sts assume-role --region us-west-2 --role-arn arn:aws:iam::123456789012:role/CrossAccountAccessFromCI --role-session-name ci-session --external-id unique-external-id-12345

# Response includes temporary credentials (AccessKeyId, SecretAccessKey, SessionToken)
# Export them:
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# Now all AWS CLI commands run against target account
aws sts get-caller-identity --region us-west-2
# Returns: arn:aws:sts::123456789012:assumed-role/CrossAccountAccessFromCI/ci-session
```

---

## Part 4: GitHub Actions OIDC Multi-Account

### Update Trust Policy for Multiple Accounts

**In each target account's GitHub OIDC role:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<TARGET_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:ClubReadyAWSDevOps/<REPO>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

**GitHub Actions workflow for multi-account deploy:**

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Configure AWS credentials (Production)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/terraform-github-actions
          aws-region: us-west-2
      
      - name: Deploy to Production
        run: terraform apply -auto-approve
  
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Configure AWS credentials (Staging)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::234567890123:role/terraform-github-actions
          aws-region: us-west-2
      
      - name: Deploy to Staging
        run: terraform apply -auto-approve
```

---

## Part 5: AWS CLI Profile Configuration

### Multi-Account SSO Profiles

**~/.aws/config:**
```ini
[default]
region = us-west-2
output = json

[profile sso-production-admin]
sso_start_url = https://d-abc123xyz.awsapps.com/start
sso_region = us-west-2
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-west-2

[profile sso-staging-readonly]
sso_start_url = https://d-abc123xyz.awsapps.com/start
sso_region = us-west-2
sso_account_id = 234567890123
sso_role_name = ReadOnlyAccess
region = us-west-2

[profile assume-production]
role_arn = arn:aws:iam::123456789012:role/CrossAccountAccessFromCI
source_profile = default
external_id = unique-external-id-12345
region = us-west-2
```

### Login and Use

```bash
# SSO login (one-time per session)
AWS_PROFILE=sso-production-admin aws sso login --region us-west-2

# Use profile via env var
AWS_PROFILE=sso-production-admin aws s3 ls --region us-west-2

# Assume role profile (uses source_profile credentials automatically)
AWS_PROFILE=assume-production aws ec2 describe-instances --region us-west-2
```

---

## Part 6: Service Control Policies (SCPs)

SCPs enforce guardrails across all accounts in an OU.

### Example: Prevent Region Access Outside us-west-2

```bash
cat > /tmp/deny-other-regions-scp.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-west-2", "us-east-1"]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/OrganizationAccountAccessRole"
        }
      }
    }
  ]
}
EOF

aws organizations create-policy --region us-west-2 --content file:///tmp/deny-other-regions-scp.json --name DenyOtherRegions --type SERVICE_CONTROL_POLICY --description "Only allow us-west-2 and us-east-1"

POLICY_ID=$(aws organizations list-policies --region us-west-2 --filter SERVICE_CONTROL_POLICY --query 'Policies[?Name==`DenyOtherRegions`].Id' --output text)

# Attach to Production OU
aws organizations attach-policy --region us-west-2 --policy-id "$POLICY_ID" --target-id "$PROD_OU_ID"
```

### Example: Prevent Deleting CloudWatch Logs

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": [
        "logs:DeleteLogGroup",
        "logs:DeleteLogStream"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Testing Multi-Account Access

### 1. Verify SSO Access

```bash
AWS_PROFILE=sso-production-admin aws sso login --region us-west-2
AWS_PROFILE=sso-production-admin aws sts get-caller-identity --region us-west-2
# Should return: arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_AdministratorAccess_.../john.doe
```

### 2. Verify Cross-Account Assume Role

```bash
aws sts assume-role --region us-west-2 --role-arn arn:aws:iam::123456789012:role/CrossAccountAccessFromCI --role-session-name test --external-id unique-external-id-12345 | jq -r '.Credentials.AccessKeyId'
# Returns: ASIA... (temporary credentials)
```

### 3. Verify SCP Enforcement

```bash
# Try creating resource in forbidden region (should fail)
AWS_PROFILE=sso-production-admin aws sso login --region us-west-2
AWS_PROFILE=sso-production-admin aws ec2 describe-instances --region eu-west-1
# Error: An error occurred (UnauthorizedOperation) when calling the DescribeInstances operation
```

---

## Best Practices

1. **Separation of Duties**
   - Management account: Only for Organizations and billing, no workloads
   - Production account: Production workloads only
   - Staging/Dev accounts: Isolated from production

2. **Centralized Logging**
   - Use AWS Control Tower or CloudTrail Organization Trail
   - Send all account logs to central S3 bucket in management account
   - Enable GuardDuty across all accounts

3. **Consistent Tagging**
   - Enforce tags via SCPs: Environment, Owner, CostCenter
   - Use Tag Policies in AWS Organizations

4. **Break Glass Access**
   - Keep root user MFA-secured in sealed envelope
   - Create OrganizationAccountAccessRole in each account for emergency access
   - Log all root usage

5. **Least Privilege**
   - Start with ReadOnly permission sets
   - Gradually add specific write permissions as needed
   - Regularly audit unused permissions via IAM Access Analyzer

---

## Troubleshooting

**Error: "User is not authorized to perform sso:CreateAccountAssignment"**
- Must be run from management account or delegated admin account
- Check IAM Identity Center admin permissions

**SSO login fails with "Session expired"**
```bash
AWS_PROFILE=sso-production-admin aws sso logout --region us-west-2
AWS_PROFILE=sso-production-admin aws sso login --region us-west-2
```

**Assume role fails with "Not authorized"**
- Check trust policy in target account includes source account ARN
- Verify external ID matches (if used)
- Check source account/user has `sts:AssumeRole` permission

**SCP blocks legitimate action**
- SCPs are cumulative deny — even admin can't override
- Detach SCP temporarily to test:
  ```bash
  aws organizations detach-policy --region us-west-2 --policy-id "$POLICY_ID" --target-id "$PROD_OU_ID"
  ```

---

## Integration

- Run `/aws-credentials-audit` across all accounts for centralized security review
- Use `/aws-architecture-review` per account to ensure consistent architecture
- Integrate with `/setup-terraform-github-oidc` for per-account OIDC roles

---

## Next Steps

- Set up AWS Control Tower for automated account vending
- Enable AWS Config for compliance monitoring across accounts
- Implement centralized VPC (Transit Gateway) for cross-account networking
- Set up consolidated billing and cost allocation tags
