#!/usr/bin/env python3
"""
Use AWS Bedrock to generate an executive summary from raw audit output.
Produces Issue #1-quality insights from raw CLI dumps.
"""

import json
import sys
import boto3
from datetime import datetime

def read_audit_file(filepath):
    """Read audit file, return empty string if missing."""
    try:
        with open(filepath, 'r') as f:
            return f.read()
    except FileNotFoundError:
        return ""

def summarize_audit(cost_file, creds_file, arch_file, ri_file):
    """Generate executive summary via Bedrock Claude Opus for deep analysis."""

    # Read all audit outputs
    cost_data = read_audit_file(cost_file)
    creds_data = read_audit_file(creds_file)
    arch_data = read_audit_file(arch_file)
    ri_data = read_audit_file(ri_file)

    # Strip emoji/non-ASCII to avoid encoding issues
    cost_clean = ''.join(c for c in cost_data if ord(c) < 128)
    creds_clean = ''.join(c for c in creds_data if ord(c) < 128)
    arch_clean = ''.join(c for c in arch_data if ord(c) < 128)
    ri_clean = ''.join(c for c in ri_data if ord(c) < 128)

    # Create comprehensive analysis prompt
    prompt = f"""You are an AWS solutions architect and FinOps expert. Analyze these 4 raw AWS CLI audit outputs and generate a comprehensive executive summary in the style of a senior consultant's report.

# RAW AUDIT DATA

## Cost Review Output
{cost_clean}

## Credentials Audit Output
{creds_clean}

## Architecture Review Output
{arch_clean}

## Reserved Capacity Review Output
{ri_clean}

---

# YOUR TASK

Synthesize the raw data above into actionable insights. Extract, calculate, and prioritize:

## 1. Executive Metrics

- **Monthly Cost**: Extract current month-to-date spend. If you see service-by-service costs, sum them. Look for patterns like "Amazon Relational Database Service: $X" or "Current Month" totals.

- **Identified Waste**: Calculate monthly waste from:
  * Stopped EC2 instances with attached EBS volumes (look for "Stopped since" entries)
  * Stale manual snapshots (age > 6 months)
  * Single-task ECS services that could share capacity
  * Old unused volumes
  Provide dollar estimate per waste source.

- **RI Savings Opportunity**: Parse Reserved Instance data:
  * RDS: Look for "On-Demand monthly: $X" and "1yr RI monthly: $Y" — calculate X - Y
  * EC2: Look for utilization percentages. If <100%, calculate waste: (reserved hours - used hours) × hourly rate
  * Savings Plans: If coverage is 0%, estimate 30-40% savings on EC2/Fargate spend
  Total all RI/SP opportunities.

- **Architecture Score**: Rate 0-100 based on:
  * -20 if root account issues (MFA disabled, old password, access keys)
  * -15 per publicly accessible database
  * -10 per single-AZ production cluster
  * -5 per missing CloudWatch Logs on RDS
  * -5 if VPC Flow Logs disabled
  * -5 per unencrypted EBS volume (cap at -20)
  * +15 if all RDS encrypted
  * +10 if auto-scaling configured
  * +10 if CloudWatch alarms present
  Start at 70, apply modifiers.

## 2. Priority Findings

Categorize findings as:
- **P0 (Critical)**: Root account issues, public databases, credentials 365+ days old
- **P1 (High)**: VPC Flow Logs disabled, secrets in Lambda env vars, RI expirations <60 days
- **P2 (Medium)**: Single-AZ non-prod, stopped instances >90 days, missing auto-scaling
- **P3 (Low)**: Stale snapshots, Graviton migration opportunities, old IAM roles

## 3. Top 5 Action Items

Rank by impact (savings or risk reduction). Format:
- Action description
- Financial impact ($X/month) or risk level (critical/high/medium)
- Urgency (days to implement)
- Effort (hours to complete)

## 4. Cost Breakdown

If service costs are listed, show top 5 services with percentages.

## 5. Reserved Instance Summary

If RI data exists:
- List active RIs with expiration dates
- Highlight expirations <60 days (urgent renewal)
- Calculate right-sizing opportunities (e.g., "reduce m8g.2xlarge from x16 to x10 based on 60% utilization")

---

# OUTPUT FORMAT

Return ONLY valid JSON (no markdown, no explanation):

{{
  "monthly_cost": <number>,
  "monthly_cost_formatted": "$X,XXX",
  "waste_monthly": <number>,
  "waste_sources": [
    {{"source": "stopped instances", "monthly_cost": <number>}},
    {{"source": "stale snapshots", "monthly_cost": <number>}}
  ],
  "ri_savings_monthly": <number>,
  "ri_details": [
    {{"type": "RDS db.r8g.xlarge", "monthly_savings": <number>, "action": "renew before 2026-08-04"}},
    {{"type": "EC2 right-sizing", "monthly_savings": <number>, "action": "reduce x16 to x10"}},
    {{"type": "Savings Plan", "monthly_savings": <number>, "action": "purchase 1yr Compute SP"}}
  ],
  "architecture_score": <number>,
  "architecture_score_rationale": "<1-2 sentence explanation>",
  "top_actions": [
    {{
      "priority": "P0|P1|P2|P3",
      "action": "<specific action>",
      "impact": "$X/month or <risk level>",
      "urgency_days": <number>,
      "effort_hours": <number>
    }}
  ],
  "cost_breakdown": [
    {{"service": "RDS", "monthly": <number>, "percent": <number>}}
  ],
  "critical_issues": [
    "<issue description>"
  ],
  "high_priority_issues": [
    "<issue description>"
  ]
}}

Be precise with numbers. If data is missing, set to 0 or null. Always calculate waste and RI savings — don't return 0 unless you genuinely found zero waste."""

    # Call Bedrock with Sonnet for deep analysis (Opus may not be available in all regions)
    bedrock = boto3.client('bedrock-runtime', region_name='us-west-2')

    response = bedrock.invoke_model(
        modelId='anthropic.claude-sonnet-4-6-v1:0',  # Use Sonnet 4.6 for analysis
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 4096,  # Increased for comprehensive output
            'messages': [{'role': 'user', 'content': prompt}]
        })
    )

    # Parse response
    result = json.loads(response['body'].read())
    summary_text = result['content'][0]['text']

    # Extract JSON from potential markdown fences
    if '```json' in summary_text:
        summary_text = summary_text.split('```json')[1].split('```')[0].strip()
    elif '```' in summary_text:
        summary_text = summary_text.split('```')[1].split('```')[0].strip()

    return summary_text

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("Usage: summarize-with-bedrock.py <cost-file> <creds-file> <arch-file> <ri-file>", file=sys.stderr)
        sys.exit(1)

    summary_json = summarize_audit(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    print(summary_json)
