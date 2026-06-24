# ClubReady AWS DevOps Skills

A collection of Claude Code skills for AWS infrastructure management, cost optimization, and operational excellence.

## Overview

This repository contains reusable skills designed for Claude Code, Claude CLI, and other AI-powered development tools. These skills codify DevOps best practices, AWS cost management workflows, and operational runbooks specific to ClubReady's AWS infrastructure.

## Installation

### For Claude Code / Claude CLI

```bash
# Clone into your project's .claude/skills directory
cd /path/to/your/project
git clone https://github.com/ClubReadyAWSDevOps/devops-skills .claude/skills/devops

# Or install globally for all projects
mkdir -p ~/.claude/skills
git clone https://github.com/ClubReadyAWSDevOps/devops-skills ~/.claude/skills/devops
```

After installation, run `/reload-plugins` in Claude Code to register the new skills.

## Available Skills

### Orchestration (Start Here!)

- **`aws-comprehensive-audit`** ⭐ — **Master orchestrator** that runs all AWS audits in parallel (cost, credentials, architecture, reserved capacity) and creates a consolidated GitHub issue with prioritized findings. Run this monthly or before major infrastructure changes.

### Cost Management

- **`aws-cost-review`** — Monthly budget analysis, spend trends, and anomaly detection across all AWS services
- **`aws-reserved-capacity`** — Reserved Instance and Savings Plans utilization review with ROI calculations

### Security & Compliance

- **`aws-credentials-audit`** — Comprehensive IAM credentials security audit (unused keys, MFA compliance, old passwords, secrets rotation)
- **`aws-architecture-review`** — Multi-dimensional architecture audit aligned with AWS Well-Architected Framework (HA, security, cost, performance, observability)

### Multi-Account & Infrastructure-as-Code

- **`aws-multi-account-access`** — Configure cross-account access for AWS Organizations with IAM Identity Center or assume-role patterns
- **`setup-terraform-github-oidc`** — Set up Terraform project with GitHub Actions OIDC authentication (keyless AWS access)

### Coming Soon

- `aws-rds-rightsizing` — Database cost optimization recommendations
- `aws-snapshot-cleanup` — Identify and clean up orphaned snapshots
- `aws-rds-health-check` — RDS cluster health and performance monitoring
- `aws-ecs-service-review` — ECS task health and resource utilization
- `cloudwatch-alarm-triage` — Investigation workflow for CloudWatch alarms

## Skill Structure

Each skill follows this format:

```
.claude/skills/
└── <skill-name>/
    └── SKILL.md     # YAML frontmatter + numbered checklist body
```

Example SKILL.md:

```yaml
---
name: aws-cost-review
description: Monthly AWS budget analysis and spend trend review
---

## AWS Cost Review

1. Fetch current month spend by service
2. Compare vs budget and last month
3. Identify top 10 cost drivers
4. Flag anomalies (>20% week-over-week increase)
5. Generate summary report
```

## Configuration

### AWS CLI Setup

Skills assume the following AWS CLI setup:

- **No `--profile` flag** — relies on ambient default profile (`AWS_PROFILE` env var)
- **Explicit `--region us-west-2`** — all commands include region flag
- **IAM authentication** — RDS connections use IAM tokens via `rds-db:connect`

For ClubReady infrastructure specifics, see [INFRASTRUCTURE.md](INFRASTRUCTURE.md).

### GitHub Actions Setup (Multi-Account)

To run automated audits across multiple AWS accounts:

1. **Add GitHub Secret for Account IDs:**
   ```
   Name: AWS_ACCOUNT_IDS
   Value: 123456789012,234567890123,345678901234
   ```
   Comma-separated list of AWS account IDs to audit.

2. **Create IAM Role in Each Account:**
   ```bash
   # Role name: aws-audit-github-actions
   # Trust policy: GitHub OIDC provider
   # Permissions: ReadOnlyAccess (or custom read-only policy)
   ```

3. **The workflow will:**
   - Parse the comma-separated account IDs
   - Run audits in parallel (max 3 concurrent)
   - Create a **separate GitHub issue for each account**
   - Label issues with `account:<account-id>` for filtering

**Manual trigger** with custom accounts:
```bash
gh workflow run monthly-aws-audit.yml -f account_ids="123456789012,999888777666"
```

### Auto-Detecting Missing Permissions

The audit automatically detects missing IAM permissions and includes them in the GitHub issue:

1. **Audit runs** and encounters `AccessDenied` errors
2. **Script extracts** the missing permission actions (e.g., `ce:GetReservationUtilization`)
3. **GitHub issue** includes a ready-to-apply IAM policy statement
4. **You review** and apply the permissions:

```bash
# Option 1: Extract from issue and apply
# (Copy the JSON from the GitHub issue to missing-permissions.json)
./scripts/add-missing-permissions.sh missing-permissions.json

# Option 2: Re-run full setup (merges with existing permissions)
./scripts/setup-iam-role-permissions.sh
```

The next audit run will have the new permissions and complete successfully.

## Development

### Creating a New Skill

1. Create a new directory under `.claude/skills/<skill-name>/`
2. Add `SKILL.md` with YAML frontmatter:
   - `name`: kebab-case identifier
   - `description`: when to trigger (be specific for tool matching)
3. Write the body as a numbered checklist or runbook
4. Use repo-root-relative paths (`./<path>`) not absolute paths
5. Test with `/reload-plugins` and `/<skill-name>` invocation

### Testing

Before committing:

1. Test the skill in a real Claude Code session
2. Verify all AWS CLI commands work without manual intervention
3. Ensure error handling is explicit (e.g., "if X fails, do Y")
4. Check that the skill is self-contained (no external file dependencies)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b skill/new-skill-name`)
3. Add your skill following the structure above
4. Update this README with the new skill in the appropriate category
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

For issues or questions:
- **Internal**: #cloud-infra-team Slack channel
- **GitHub Issues**: https://github.com/ClubReadyAWSDevOps/devops-skills/issues
