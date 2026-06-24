#!/bin/bash
set -euo pipefail

# Setup script to add audit + Bedrock permissions to existing github-actions-claude-review role

ROLE_NAME="github-actions-claude-review"
POLICY_NAME="GitHubActionsAuditAndBedrock"
POLICY_FILE="$(dirname "$0")/../docs/iam-policy-github-actions.json"

echo "🔧 Setting up IAM permissions for GitHub Actions role..."
echo "Role: $ROLE_NAME"
echo "Policy: $POLICY_NAME"
echo ""

# Check if role exists
if ! aws iam get-role --region us-west-2 --role-name "$ROLE_NAME" &>/dev/null; then
  echo "❌ Error: Role '$ROLE_NAME' does not exist"
  echo ""
  echo "Create it first with OIDC trust policy:"
  echo "  aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json"
  exit 1
fi

echo "✅ Role exists"

# Check if policy file exists
if [ ! -f "$POLICY_FILE" ]; then
  echo "❌ Error: Policy file not found: $POLICY_FILE"
  exit 1
fi

echo "✅ Policy file found"
echo ""

# Validate JSON
if ! jq empty "$POLICY_FILE" 2>/dev/null; then
  echo "❌ Error: Invalid JSON in policy file"
  exit 1
fi

echo "✅ Policy JSON is valid"
echo ""

# Check if inline policy already exists
if aws iam get-role-policy --region us-west-2 --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" &>/dev/null; then
  echo "⚠️  Policy '$POLICY_NAME' already exists on role"
  read -p "Do you want to update it? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping policy update"
    exit 0
  fi
fi

# Apply the policy
echo "📝 Applying policy to role..."
aws iam put-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "file://$POLICY_FILE"

echo ""
echo "✅ Policy applied successfully"
echo ""

# Verify the policy
echo "📋 Verifying policy..."
aws iam get-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'PolicyDocument.Statement[*].[Sid,Effect]' \
  --output table

echo ""
echo "🎉 Setup complete!"
echo ""
echo "The role '$ROLE_NAME' now has:"
echo "  ✅ Bedrock invoke permissions (Claude models)"
echo "  ✅ Cost Explorer read permissions"
echo "  ✅ IAM credential report access"
echo "  ✅ RDS, EC2, ECS, S3 read permissions"
echo "  ✅ CloudWatch, Secrets Manager read access"
echo "  ✅ Organizations, SSO read access"
echo ""
echo "Next steps:"
echo "1. Add AWS_ACCOUNT_IDS secret to GitHub repository"
echo "2. Run workflow manually or wait for monthly cron"
echo ""
