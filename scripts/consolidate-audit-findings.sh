#!/bin/bash
set -euo pipefail

# Consolidate AWS audit findings into a single GitHub issue report

AUDIT_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")
REPORT_FILE="/tmp/consolidated-audit-report.md"
MISSING_PERMS_FILE="/tmp/missing-permissions.json"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-N/A}"
AWS_ACCOUNT_ALIAS="${AWS_ACCOUNT_ALIAS:-Unknown}"

# Initialize missing permissions tracking
echo '[]' > "$MISSING_PERMS_FILE"

# Function to extract missing permissions from AWS CLI errors
extract_missing_permissions() {
  local audit_file=$1

  if [ ! -f "$audit_file" ]; then
    return
  fi

  # Look for AccessDenied errors and extract the action
  # Example: "An error occurred (AccessDenied) when calling the GetCostAndUsage operation"
  # Example: "User: arn:aws:sts::123:assumed-role/role is not authorized to perform: ce:GetCostAndUsage"

  while IFS= read -r line; do
    # Pattern 1: "is not authorized to perform: <action>"
    if echo "$line" | grep -q "is not authorized to perform:"; then
      ACTION=$(echo "$line" | sed -n 's/.*is not authorized to perform: \([a-zA-Z0-9:*]\+\).*/\1/p' | head -1)
      if [ -n "$ACTION" ]; then
        # Add to missing permissions array
        jq --arg action "$ACTION" '. += [$action] | unique' "$MISSING_PERMS_FILE" > "$MISSING_PERMS_FILE.tmp"
        mv "$MISSING_PERMS_FILE.tmp" "$MISSING_PERMS_FILE"
      fi
    fi

    # Pattern 2: "AccessDenied) when calling the <Operation> operation"
    if echo "$line" | grep -qE "AccessDenied.*calling the [A-Za-z]+ operation"; then
      OPERATION=$(echo "$line" | sed -n 's/.*calling the \([A-Za-z]\+\) operation.*/\1/p' | head -1)
      # Try to infer the service from the audit file name
      SERVICE=""
      case "$audit_file" in
        *cost-review*) SERVICE="ce" ;;
        *credentials-audit*) SERVICE="iam" ;;
        *architecture-review*) SERVICE="ec2" ;;  # Could be multiple
        *reserved-capacity*) SERVICE="ce" ;;
      esac

      if [ -n "$OPERATION" ] && [ -n "$SERVICE" ]; then
        ACTION="$SERVICE:$OPERATION"
        jq --arg action "$ACTION" '. += [$action] | unique' "$MISSING_PERMS_FILE" > "$MISSING_PERMS_FILE.tmp"
        mv "$MISSING_PERMS_FILE.tmp" "$MISSING_PERMS_FILE"
      fi
    fi
  done < "$audit_file"
}

# Initialize report
cat > "$REPORT_FILE" <<EOF
# AWS Infrastructure Audit — $AWS_ACCOUNT_ALIAS

**Account ID:** \`$AWS_ACCOUNT_ID\`
**Audit Date:** $AUDIT_DATE

EOF

# Track overall statistics
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0

# Function to extract findings from audit output
extract_findings() {
  local audit_file=$1
  local audit_name=$2
  local status=$3

  echo "" >> "$REPORT_FILE"
  echo "<details>" >> "$REPORT_FILE"
  echo "<summary>📊 $audit_name $([ "$status" != "0" ] && echo "⚠️ FAILED" || echo "✅")</summary>" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  if [ -f "$audit_file" ]; then
    echo '```' >> "$REPORT_FILE"
    head -500 "$audit_file" >> "$REPORT_FILE"  # Limit to 500 lines
    echo '```' >> "$REPORT_FILE"
  else
    echo "No output captured." >> "$REPORT_FILE"
  fi

  echo "" >> "$REPORT_FILE"
  echo "</details>" >> "$REPORT_FILE"
}

# Extract missing permissions from all audit files
for audit_file in /tmp/*-review.txt /tmp/*-audit.txt; do
  if [ -f "$audit_file" ]; then
    extract_missing_permissions "$audit_file"
  fi
done

# Extract key metrics from cost review
if [ -f /tmp/cost-review.txt ]; then
  # Try formatted output first (claude-code-action style)
  MONTHLY_COST=$(grep "Current Month" /tmp/cost-review.txt | head -1 | sed -n 's/.*\$\([0-9,.]\+\).*/\1/p' || echo "")

  # If not found, calculate from raw service costs (Python script style)
  if [ -z "$MONTHLY_COST" ] || [ "$MONTHLY_COST" = "N/A" ]; then
    # Extract only the first block of service costs (stop at first " - null:" line)
    # Take lines between "Generated:" and first " - null:" that match "Service: $XXX" pattern
    MONTHLY_COST=$(awk '/Generated:/{flag=1; next} flag && / - null:/{exit} flag && /: \$[0-9]+/' /tmp/cost-review.txt | grep -oE '\$[0-9]+' | sed 's/\$//' | awk '{sum+=$1} END {printf "%.2f", sum}')
    # If still empty, mark as N/A
    if [ -z "$MONTHLY_COST" ]; then
      MONTHLY_COST="N/A"
    fi
  fi

  WASTE=$(grep -i "waste" /tmp/cost-review.txt | sed -n 's/.*\$\([0-9,.]\+\).*/\1/p' | head -1 || echo "0")
else
  MONTHLY_COST="N/A"
  WASTE="0"
fi

# Extract critical issues from credentials audit
if [ -f /tmp/credentials-audit.txt ]; then
  CRITICAL_COUNT=$(grep -c "🔴" /tmp/credentials-audit.txt || echo "0")
  HIGH_COUNT=$(grep -c "⚠️" /tmp/credentials-audit.txt || echo "0")
fi

# Extract architecture score
if [ -f /tmp/architecture-review.txt ]; then
  ARCH_SCORE=$(grep "OVERALL SCORE:" /tmp/architecture-review.txt | sed -n 's/.*OVERALL SCORE: [A-F]* (\([0-9]\+\).*/\1/p' | head -1 || echo "N/A")
  if [ -z "$ARCH_SCORE" ]; then
    ARCH_SCORE="N/A"
  fi
else
  ARCH_SCORE="N/A"
fi

# Extract RI savings potential
if [ -f /tmp/reserved-capacity.txt ]; then
  # Try formatted "Total Monthly Savings Potential: $XXX" first
  RI_SAVINGS=$(grep "Total Monthly Savings Potential:" /tmp/reserved-capacity.txt | sed -n 's/.*\$\([0-9,.]\+\).*/\1/p' | head -1 || echo "")

  # If not found, calculate from "On-Demand monthly" minus "1yr RI monthly"
  if [ -z "$RI_SAVINGS" ]; then
    ON_DEMAND=$(grep "On-Demand monthly:" /tmp/reserved-capacity.txt | awk '{print $NF}' | head -1)
    RI_MONTHLY=$(grep "1yr RI monthly" /tmp/reserved-capacity.txt | awk '{print $NF}' | head -1)

    if [ -n "$ON_DEMAND" ] && [ -n "$RI_MONTHLY" ]; then
      RI_SAVINGS=$(echo "$ON_DEMAND - $RI_MONTHLY" | bc | xargs printf "%.2f")
    else
      RI_SAVINGS="0"
    fi
  fi

  if [ -z "$RI_SAVINGS" ]; then
    RI_SAVINGS="0"
  fi
else
  RI_SAVINGS="0"
fi

# Write executive summary
cat >> "$REPORT_FILE" <<EOF
## Executive Summary

| Metric | Value |
|--------|-------|
| **Monthly Cost** | \$$MONTHLY_COST |
| **Identified Waste** | \$$WASTE/month |
| **RI Savings Opportunity** | \$$RI_SAVINGS/month |
| **Architecture Score** | $ARCH_SCORE/100 |
| **Critical Issues** | $CRITICAL_COUNT 🔴 |
| **High Priority** | $HIGH_COUNT 🟠 |

---

## Priority Findings

### 🔴 Critical Issues (P0)

EOF

# Extract critical findings from each audit
if [ -f /tmp/credentials-audit.txt ]; then
  grep "🔴" /tmp/credentials-audit.txt | head -5 | sed 's/^/- /' >> "$REPORT_FILE" || echo "None found" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

### 🟠 High Priority (P1)

EOF

# Extract high priority findings
if [ -f /tmp/cost-review.txt ]; then
  grep -A5 "Action Items:" /tmp/cost-review.txt | tail -3 | sed 's/^/- [cost] /' >> "$REPORT_FILE" || echo "None found" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

### 🟡 Medium Priority (P2)

EOF

# Extract medium priority findings from architecture review
if [ -f /tmp/architecture-review.txt ]; then
  grep "⚠️" /tmp/architecture-review.txt | head -3 | sed 's/^/- [architecture] /' >> "$REPORT_FILE" || echo "None found" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

---

## Detailed Findings

EOF

# Append full audit outputs as collapsible sections
extract_findings "/tmp/cost-review.txt" "Cost Review" "${COST_STATUS:-0}"
extract_findings "/tmp/credentials-audit.txt" "Credentials Audit" "${CREDS_STATUS:-0}"
extract_findings "/tmp/architecture-review.txt" "Architecture Review" "${ARCH_STATUS:-0}"
extract_findings "/tmp/reserved-capacity.txt" "Reserved Capacity Review" "${RI_STATUS:-0}"

# Add next steps
# Check if we found any missing permissions
MISSING_PERMS_COUNT=$(jq 'length' "$MISSING_PERMS_FILE")

if [ "$MISSING_PERMS_COUNT" -gt 0 ]; then
  cat >> "$REPORT_FILE" <<EOF

---

## ⚠️ Missing IAM Permissions Detected

The audit encountered **$MISSING_PERMS_COUNT permission error(s)**. Add these permissions to the \`github-actions-claude-review\` IAM role:

<details>
<summary>📋 Required IAM Permissions (Click to expand)</summary>

\`\`\`json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AdditionalAuditPermissions",
      "Effect": "Allow",
      "Action": [
EOF

  # Add each missing permission as a JSON array item
  jq -r '.[] | "        \"" + . + "\","' "$MISSING_PERMS_FILE" | sed '$ s/,$//' >> "$REPORT_FILE"

  cat >> "$REPORT_FILE" <<'EOF'
      ],
      "Resource": "*"
    }
  ]
}
```

**To apply these permissions:**

```bash
# Option 1: Automated (recommended)
cd ~/projects/devops-skills
./scripts/setup-iam-role-permissions.sh

# Option 2: Manual
aws iam put-role-policy --region us-west-2 \
  --role-name github-actions-claude-review \
  --policy-name AdditionalAuditPermissions \
  --policy-document file://<(cat <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
EOF

  jq -r '.[] | "        \"" + . + "\","' "$MISSING_PERMS_FILE" | sed '$ s/,$//' >> "$REPORT_FILE"

  cat >> "$REPORT_FILE" <<'EOF'
      ],
      "Resource": "*"
    }
  ]
}
POLICY
)
```

**Missing Actions:**
EOF

  # List missing actions as bullet points
  jq -r '.[] | "- `" + . + "`"' "$MISSING_PERMS_FILE" >> "$REPORT_FILE"

  cat >> "$REPORT_FILE" <<EOF

</details>

EOF
fi

cat >> "$REPORT_FILE" <<EOF

---

## Next Steps

- [ ] **P0 (Critical):** Address immediately (within 24 hours)
- [ ] **P1 (High):** Review and assign owners this week
- [ ] **P2 (Medium):** Evaluate for next sprint
- [ ] **P3 (Low):** Backlog for future improvements
EOF

if [ "$MISSING_PERMS_COUNT" -gt 0 ]; then
  cat >> "$REPORT_FILE" <<EOF
- [ ] **IAM Permissions:** Add $MISSING_PERMS_COUNT missing permission(s) to role
EOF
fi

cat >> "$REPORT_FILE" <<EOF

---

**Generated by:** [aws-comprehensive-audit](https://github.com/ClubReadyAWSDevOps/devops-skills)
**Audit Date:** $AUDIT_DATE
**Workflow Run:** [#${GITHUB_RUN_NUMBER:-N/A}](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-ClubReadyAWSDevOps/devops-skills}/actions/runs/${GITHUB_RUN_ID:-0})
EOF

echo "✅ Consolidated report written to $REPORT_FILE"
cat "$REPORT_FILE"
