---
name: setup-terraform-github-oidc
description: Set up Terraform project with GitHub Actions OIDC authentication to AWS (no long-lived credentials). Use when creating new infrastructure-as-code projects or migrating from access keys to OIDC.
---

## Setup Terraform with GitHub Actions OIDC

Step-by-step guide to create a Terraform project that uses GitHub Actions OIDC (OpenID Connect) for secure, keyless AWS authentication — no access keys or secrets required.

### Architecture

```
GitHub Actions Workflow
  ↓ (OIDC token)
AWS IAM Identity Provider
  ↓ (assume role)
IAM Role (terraform-github-actions)
  ↓ (scoped permissions)
Terraform Apply (RDS, ECS, S3, etc.)
```

### Prerequisites

- AWS account with IAM admin access
- GitHub repository in ClubReadyAWSDevOps org
- Terraform >= 1.5
- AWS CLI configured

---

## Part 1: AWS IAM Setup

### 1. Create OIDC Identity Provider (one-time per AWS account)

```bash
aws iam create-open-id-connect-provider --region us-west-2 --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**Verify creation:**
```bash
aws iam list-open-id-connect-providers --region us-west-2 | jq -r '.OpenIDConnectProviderList[] | select(.Arn | contains("token.actions.githubusercontent.com"))'
```

### 2. Create IAM Role for GitHub Actions

**trust-policy.json:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ClubReadyAWSDevOps/<REPO_NAME>:*"
        }
      }
    }
  ]
}
```

**Create role:**
```bash
aws iam create-role --region us-west-2 --role-name terraform-github-actions --assume-role-policy-document file://trust-policy.json --description "GitHub Actions OIDC role for Terraform"
```

### 3. Attach Terraform Permissions Policy

**terraform-permissions.json** (adjust for your resources):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "ec2:Describe*",
        "ec2:CreateTags",
        "ecs:*",
        "s3:*",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "logs:CreateLogGroup",
        "logs:PutRetentionPolicy",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::terraform-state-<project-name>/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-west-2:<AWS_ACCOUNT_ID>:table/terraform-locks"
    }
  ]
}
```

**Attach policy:**
```bash
aws iam put-role-policy --region us-west-2 --role-name terraform-github-actions --policy-name TerraformPermissions --policy-document file://terraform-permissions.json
```

### 4. Create Terraform State Backend (S3 + DynamoDB)

```bash
# S3 bucket for state
aws s3api create-bucket --region us-west-2 --bucket terraform-state-<project-name> --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-bucket-versioning --region us-west-2 --bucket terraform-state-<project-name> --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --region us-west-2 --bucket terraform-state-<project-name> --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --region us-west-2 --bucket terraform-state-<project-name> --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB table for state locking
aws dynamodb create-table --region us-west-2 --table-name terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

---

## Part 2: Terraform Project Setup

### 1. Create Repository Structure

```bash
mkdir -p terraform-<project-name>/{environments/production,modules}
cd terraform-<project-name>
git init
```

**Directory layout:**
```
terraform-<project-name>/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       └── terraform-apply.yml
├── environments/
│   ├── production/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── staging/
│       └── ... (same structure)
├── modules/
│   ├── rds-aurora/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── ecs-service/
│       └── ... (same structure)
├── .gitignore
└── README.md
```

### 2. Configure Terraform Backend

**environments/production/backend.tf:**
```hcl
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "terraform-state-<project-name>"
    key            = "production/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = "us-west-2"
  
  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
      Project     = "<project-name>"
    }
  }
}
```

### 3. Sample Terraform Configuration

**environments/production/main.tf:**
```hcl
module "app_rds" {
  source = "../../modules/rds-aurora"
  
  cluster_identifier = "app-prod"
  engine            = "aurora-postgresql"
  engine_version    = "15.4"
  instance_class    = "db.r6g.2xlarge"
  instance_count    = 2
  
  database_name = "app_production"
  master_username = "dbadmin"
  
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.rds.id]
  
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  
  tags = {
    Service = "application"
  }
}
```

**environments/production/variables.tf:**
```hcl
variable "vpc_id" {
  description = "VPC ID for RDS cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS (multi-AZ)"
  type        = list(string)
}
```

**environments/production/terraform.tfvars:**
```hcl
vpc_id             = "vpc-0abc123def456"
private_subnet_ids = ["subnet-0123abc", "subnet-0456def"]
```

---

## Part 3: GitHub Actions Workflows

### 1. Terraform Plan Workflow (PR trigger)

**.github/workflows/terraform-plan.yml:**
```yaml
name: Terraform Plan

on:
  pull_request:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'
      - '.github/workflows/terraform-*.yml'

permissions:
  id-token: write   # Required for OIDC
  contents: read
  pull-requests: write  # To post plan as PR comment

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [production, staging]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<AWS_ACCOUNT_ID>:role/terraform-github-actions
          aws-region: us-west-2
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.7
      
      - name: Terraform Init
        working-directory: environments/${{ matrix.environment }}
        run: terraform init
      
      - name: Terraform Format Check
        working-directory: environments/${{ matrix.environment }}
        run: terraform fmt -check -recursive
      
      - name: Terraform Validate
        working-directory: environments/${{ matrix.environment }}
        run: terraform validate
      
      - name: Terraform Plan
        working-directory: environments/${{ matrix.environment }}
        run: terraform plan -out=tfplan -no-color
      
      - name: Post Plan to PR
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('environments/${{ matrix.environment }}/tfplan.txt', 'utf8');
            const body = `## Terraform Plan: ${{ matrix.environment }}\n\`\`\`\n${plan}\n\`\`\``;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
```

### 2. Terraform Apply Workflow (main merge trigger)

**.github/workflows/terraform-apply.yml:**
```yaml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [production]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<AWS_ACCOUNT_ID>:role/terraform-github-actions
          aws-region: us-west-2
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.7
      
      - name: Terraform Init
        working-directory: environments/${{ matrix.environment }}
        run: terraform init
      
      - name: Terraform Apply
        working-directory: environments/${{ matrix.environment }}
        run: terraform apply -auto-approve
```

---

## Part 4: Testing & Validation

### 1. Test OIDC Authentication Locally (optional)

GitHub Actions will authenticate automatically via OIDC. To test locally, use traditional AWS credentials:

```bash
cd environments/production
terraform init
terraform plan
```

### 2. Test via Pull Request

1. Create a feature branch: `git checkout -b feat/add-rds-cluster`
2. Modify Terraform config
3. Commit and push: `git push origin feat/add-rds-cluster`
4. Open PR → GitHub Actions runs `terraform plan`
5. Review plan output in PR comments
6. Merge PR → GitHub Actions runs `terraform apply`

### 3. Verify State Backend

```bash
aws s3 ls s3://terraform-state-<project-name>/production/ --region us-west-2
aws dynamodb scan --region us-west-2 --table-name terraform-locks
```

---

## Security Best Practices

1. **Least-Privilege IAM Role**
   - Only grant permissions Terraform actually needs
   - Use `Resource` constraints (not `"*"`) where possible
   - Regularly audit role permissions

2. **State File Protection**
   - S3 versioning enabled (rollback on corruption)
   - Encryption at rest (AES256 or KMS)
   - Public access blocked
   - State contains secrets — never commit `*.tfstate` to git

3. **Branch Protection**
   - Require PR reviews before merge to `main`
   - Require `terraform plan` checks to pass
   - Prevent direct pushes to `main`

4. **OIDC Token Scope**
   - Trust policy limits to `ClubReadyAWSDevOps/<repo>:*`
   - Each repo gets its own IAM role (not shared)
   - Use `ref:refs/heads/main` condition to restrict to main branch only (optional)

5. **.gitignore**
   ```
   # Terraform
   **/.terraform/
   *.tfstate
   *.tfstate.backup
   *.tfplan
   .terraform.lock.hcl
   
   # Sensitive
   *.tfvars   # Commit example.tfvars, not real values
   override.tf
   ```

---

## Troubleshooting

**Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"**
- Check trust policy `sub` condition matches `repo:ClubReadyAWSDevOps/<repo>:*`
- Verify OIDC provider exists: `aws iam list-open-id-connect-providers`
- Ensure `id-token: write` permission in workflow

**Error: "Backend initialization required"**
- S3 bucket or DynamoDB table doesn't exist
- IAM role lacks S3/DynamoDB permissions
- Run `terraform init -reconfigure`

**Error: "Error acquiring the state lock"**
- Another workflow is running `terraform apply`
- Stale lock from failed run:
  ```bash
  aws dynamodb get-item --region us-west-2 --table-name terraform-locks --key '{"LockID":{"S":"terraform-state-<project>/production/terraform.tfstate-md5"}}'
  # If safe, delete:
  aws dynamodb delete-item --region us-west-2 --table-name terraform-locks --key '{"LockID":{"S":"..."}}'
  ```

---

## Integration with Existing Projects

To add OIDC to an existing Terraform project with access keys:

1. Complete Part 1 (AWS IAM setup)
2. Update `.github/workflows/*.yml` to use `aws-actions/configure-aws-credentials@v4` with `role-to-assume`
3. Remove GitHub Secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
4. Test with a PR to non-production environment first
5. Once validated, roll out to production workflows

---

## Next Steps

- Add `tflint` to workflows for Terraform linting
- Set up Terraform Cloud/Spacelift for enhanced state management
- Create reusable modules under `modules/` for common patterns
- Add cost estimation with Infracost action
- Implement drift detection (scheduled `terraform plan` runs)
