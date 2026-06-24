#!/bin/bash
set -euo pipefail

# Complete IAM role setup for GitHub Actions OIDC authentication
# Run this script in each AWS account you want to audit

ROLE_NAME="github-actions-claude-review"
POLICY_NAME="GitHubActionsAuditAndBedrock"
GITHUB_ORG="ClubReadyAWSDevOps"
GITHUB_REPO="devops-skills"
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

echo "🚀 Setting up GitHub Actions IAM role for AWS audits"
echo ""
echo "Account: $(aws sts get-caller-identity --region us-west-2 --query Account --output text)"
echo "Role: $ROLE_NAME"
echo "Repository: $GITHUB_ORG/$GITHUB_REPO"
echo ""

# Step 1: Create OIDC Identity Provider (if it doesn't exist)
echo "1️⃣ Setting up OIDC Identity Provider..."

OIDC_ARN=$(aws iam list-open-id-connect-providers --region us-west-2 --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_URL')].Arn" --output text)

if [ -z "$OIDC_ARN" ]; then
  echo "   Creating OIDC provider for GitHub Actions..."

  aws iam create-open-id-connect-provider --region us-west-2 \
    --url "https://$OIDC_PROVIDER_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list "$OIDC_THUMBPRINT"

  OIDC_ARN=$(aws iam list-open-id-connect-providers --region us-west-2 --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_URL')].Arn" --output text)
  echo "   ✅ OIDC provider created: $OIDC_ARN"
else
  echo "   ✅ OIDC provider already exists: $OIDC_ARN"
fi

echo ""

# Step 2: Create trust policy for the role
echo "2️⃣ Creating trust policy..."

ACCOUNT_ID=$(aws sts get-caller-identity --region us-west-2 --query Account --output text)

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$OIDC_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_ORG/$GITHUB_REPO:*"
        }
      }
    }
  ]
}
EOF

echo "   ✅ Trust policy created"
echo ""

# Step 3: Create IAM role (or update trust policy if exists)
echo "3️⃣ Creating IAM role..."

if aws iam get-role --region us-west-2 --role-name "$ROLE_NAME" &>/dev/null; then
  echo "   ⚠️  Role already exists, updating trust policy..."

  aws iam update-assume-role-policy --region us-west-2 \
    --role-name "$ROLE_NAME" \
    --policy-document file:///tmp/trust-policy.json

  echo "   ✅ Trust policy updated"
else
  echo "   Creating new role..."

  aws iam create-role --region us-west-2 \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "GitHub Actions OIDC role for AWS audits and Bedrock access"

  echo "   ✅ Role created"
fi

ROLE_ARN=$(aws iam get-role --region us-west-2 --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "   Role ARN: $ROLE_ARN"
echo ""

# Step 4: Apply permissions policy
echo "4️⃣ Applying permissions policy..."

POLICY_FILE="$(dirname "$0")/../docs/iam-policy-github-actions.json"

if [ ! -f "$POLICY_FILE" ]; then
  echo "   ❌ Error: Policy file not found: $POLICY_FILE"
  echo "   Make sure you're running this script from the devops-skills repository"
  exit 1
fi

# Validate JSON
if ! jq empty "$POLICY_FILE" 2>/dev/null; then
  echo "   ❌ Error: Invalid JSON in policy file"
  exit 1
fi

aws iam put-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "file://$POLICY_FILE"

echo "   ✅ Permissions policy applied"
echo ""

# Step 5: Verify Bedrock model access
echo "5️⃣ Verifying Bedrock model access..."

MODEL_ID="anthropic.claude-sonnet-4-6"
MODEL_NAME="Claude Sonnet 4.6"

# Check if Anthropic models are accessible
if aws bedrock list-foundation-models --region us-west-2 --by-provider anthropic --query "modelSummaries[?contains(modelId, 'sonnet-4-6')].modelId" --output text 2>/dev/null | grep -q "sonnet-4-6"; then
  echo "   ✅ $MODEL_NAME is accessible"
else
  echo "   ❌ $MODEL_NAME NOT accessible"
  echo "   📝 Enable model access in Bedrock Console:"
  echo "   1. Go to: https://console.aws.amazon.com/bedrock/home?region=us-west-2#/modelaccess"
  echo "   2. Click 'Enable specific models' or 'Manage model access'"
  echo "   3. Check: Anthropic Claude Sonnet 4.6"
  echo "   4. Click 'Request model access'"
  echo "   5. Wait ~2 minutes for approval (usually instant)"
  echo ""
  echo "   ⚠️  WARNING: Audits will fail without Bedrock model access"
fi

echo ""

# Step 6: Verify setup
echo "6️⃣ Verifying setup..."

# Check policy statements
STATEMENT_COUNT=$(aws iam get-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'length(PolicyDocument.Statement)' \
  --output text)

echo "   ✅ Policy has $STATEMENT_COUNT permission statements"

# List key permissions
echo ""
echo "   📋 Key permissions enabled:"
aws iam get-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'PolicyDocument.Statement[*].Sid' \
  --output text | tr '\t' '\n' | sed 's/^/      ✓ /'

echo ""
echo "🎉 Setup complete!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Role ARN: $ROLE_ARN"
echo "  Account:  $ACCOUNT_ID"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Run this script in each AWS account you want to audit"
echo "  2. Add account IDs to GitHub secret: AWS_ACCOUNT_IDS"
echo "  3. Trigger workflow: gh workflow run monthly-aws-audit.yml"
echo ""

# Cleanup temp files
rm -f /tmp/trust-policy.json
