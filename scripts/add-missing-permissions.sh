#!/bin/bash
set -euo pipefail

# Add missing permissions detected during audit runs to the IAM role

ROLE_NAME="${ROLE_NAME:-github-actions-claude-review}"
POLICY_NAME="GitHubActionsAuditAndBedrock"
MISSING_PERMS_FILE="${1:-/tmp/missing-permissions.json}"

if [ ! -f "$MISSING_PERMS_FILE" ]; then
  echo "❌ Error: Missing permissions file not found: $MISSING_PERMS_FILE"
  echo ""
  echo "Usage: $0 [missing-permissions.json]"
  echo ""
  echo "This script is typically run after an audit finds missing permissions."
  echo "The GitHub issue will contain the missing permissions JSON."
  exit 1
fi

MISSING_COUNT=$(jq 'length' "$MISSING_PERMS_FILE")

if [ "$MISSING_COUNT" -eq 0 ]; then
  echo "✅ No missing permissions to add"
  exit 0
fi

echo "🔧 Adding $MISSING_COUNT missing permission(s) to role..."
echo "Role: $ROLE_NAME"
echo "Policy: $POLICY_NAME"
echo ""

# Get current policy document
CURRENT_POLICY=$(aws iam get-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'PolicyDocument' \
  --output json 2>/dev/null || echo '{"Version":"2012-10-17","Statement":[]}')

echo "📋 Missing permissions:"
jq -r '.[] | "  - " + .' "$MISSING_PERMS_FILE"
echo ""

# Check if AdditionalAuditPermissions statement already exists
HAS_ADDITIONAL_STMT=$(echo "$CURRENT_POLICY" | jq '[.Statement[] | select(.Sid == "AdditionalAuditPermissions")] | length')

if [ "$HAS_ADDITIONAL_STMT" -gt 0 ]; then
  echo "📝 Merging with existing AdditionalAuditPermissions statement..."

  # Merge new permissions with existing AdditionalAuditPermissions
  UPDATED_POLICY=$(echo "$CURRENT_POLICY" | jq --slurpfile missing "$MISSING_PERMS_FILE" '
    .Statement |= map(
      if .Sid == "AdditionalAuditPermissions" then
        .Action = (.Action + $missing[0]) | unique | sort
      else
        .
      end
    )
  ')
else
  echo "📝 Adding new AdditionalAuditPermissions statement..."

  # Add new statement
  UPDATED_POLICY=$(echo "$CURRENT_POLICY" | jq --slurpfile missing "$MISSING_PERMS_FILE" '
    .Statement += [{
      "Sid": "AdditionalAuditPermissions",
      "Effect": "Allow",
      "Action": $missing[0] | sort,
      "Resource": "*"
    }]
  ')
fi

# Save to temp file
echo "$UPDATED_POLICY" > /tmp/updated-policy.json

# Validate JSON
if ! jq empty /tmp/updated-policy.json 2>/dev/null; then
  echo "❌ Error: Generated invalid JSON policy"
  exit 1
fi

echo "✅ Policy JSON validated"
echo ""

# Show diff
echo "📊 Policy changes:"
echo "Before: $(echo "$CURRENT_POLICY" | jq -r '[.Statement[].Action // []] | flatten | length') total actions"
echo "After:  $(jq -r '[.Statement[].Action // []] | flatten | length' /tmp/updated-policy.json) total actions"
echo ""

# Confirm before applying
read -p "Apply these changes? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 0
fi

# Apply updated policy
aws iam put-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/updated-policy.json

echo ""
echo "✅ Permissions added successfully"
echo ""

# Verify
echo "📋 Verifying updated policy..."
aws iam get-role-policy --region us-west-2 \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --query 'PolicyDocument.Statement[?Sid==`AdditionalAuditPermissions`].Action' \
  --output json | jq -r '.[] | .[] | "  ✓ " + .'

echo ""
echo "🎉 Complete! Re-run the audit to verify all permissions are now available."
