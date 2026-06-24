# ClubReady AWS DevOps Skills — Claude Code Instructions

This repository contains reusable Claude Code skills for AWS infrastructure management, cost optimization, and operational excellence.

## Repository Purpose

Codify DevOps best practices, AWS cost management workflows, and operational runbooks as executable skills. Each skill is a self-contained, tested workflow that can be invoked via Claude Code, Claude CLI, or other AI development tools.

## Skill Authoring Conventions

### Structure

Every skill lives in `.claude/skills/<skill-name>/SKILL.md`:

```
.claude/skills/
└── aws-cost-review/
    └── SKILL.md     # YAML frontmatter + numbered workflow
```

### Frontmatter Format

```yaml
---
name: aws-cost-review
description: When to trigger this skill — be specific for tool matching. Use for [scenario], when [condition], or to [goal].
---
```

**Name:** kebab-case, matches directory name
**Description:** Triggering conditions (200 chars max) — guides the Skill tool's matching logic

### Body Format

Use **numbered lists** for sequential workflows or **H3 sections** for reference material.

**Sequential workflow example:**
```markdown
## AWS Cost Review

1. **Fetch current month spend**
   ```bash
   aws ce get-cost-and-usage --region us-west-2 ...
   ```

2. **Compare vs last month**
   Brief explanation of what this step does
   ```bash
   aws ce get-cost-and-usage --region us-west-2 ...
   ```

3. **Generate summary report**
   - Current month: $X
   - Last month: $Y
   - Trend: Z%
```

**Reference material example:**
```markdown
## Architecture Dimensions

### 1. High Availability
Check Multi-AZ, backup retention, failover tested

### 2. Security Posture
Encryption, network isolation, IAM least privilege
```

### AWS CLI Patterns

**ALWAYS follow these patterns in every skill:**

1. **No `--profile` flag** — omit entirely; rely on ambient default profile or `AWS_PROFILE` env var
2. **Explicit `--region us-west-2`** — include in EVERY AWS CLI command for unambiguous execution
3. **Single-line commands** — never use backslash continuations (user workflow: triple-click to copy)

```bash
# ✅ Correct
aws rds describe-db-instances --region us-west-2 --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]' --output table

# ❌ Wrong — has --profile
aws rds describe-db-instances --region us-west-2 --profile production

# ❌ Wrong — multi-line with backslash
aws rds describe-db-instances \
  --region us-west-2 \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]'
```

When a command is genuinely too long, break into multiple separate one-line commands with `&&` or save to a script.

### Code Blocks

Use fenced code blocks with language hints:

````markdown
```bash
aws s3 ls s3://bucket-name --region us-west-2
```

```json
{
  "Version": "2012-10-17",
  "Statement": [...]
}
```

```yaml
name: Terraform Apply
on: [push]
```
````

### Output Format Examples

Always include an **Output Format** section showing what the skill produces:

```markdown
### Output Format

\```
=== AWS Cost Review: June 2026 ===

Current Month (MTD): $45,230
Last Month (Full):   $52,100 (-13%)

Top 5 Services:
1. RDS: $18,500 (41%)
2. EC2: $12,200 (27%)
...

Action Items:
1. Investigate RDS spike on 2026-06-15
2. Review Development EC2 usage (over budget)
\```
```

### Integration Sections

Link related skills at the end:

```markdown
### Integration with Other Skills

After identifying high-cost resources:
- **RDS high cost** → run `/aws-rds-rightsizing`
- **Snapshot cost high** → run `/aws-snapshot-cleanup`
- **Low RI utilization** → run `/aws-reserved-capacity`
```

### Notes Section

Add caveats, prerequisites, or non-obvious details:

```markdown
### Notes

- Cost Explorer data has 24-hour lag — "today" reflects yesterday
- Requires `jq` installed for JSON parsing
- IAM permissions needed: `ce:GetCostAndUsage`, `budgets:ViewBudget`
```

## Testing Skills

### Before Committing a New Skill

1. **Test in real Claude Code session**
   ```bash
   cd /path/to/devops-skills
   claude
   # In session:
   /reload-plugins
   /<your-skill-name>
   ```

2. **Verify AWS CLI commands execute without errors**
   - Copy each command from the skill
   - Run in terminal (substitute placeholders with real values)
   - Confirm output matches expected format

3. **Check self-containment**
   - Skill should not reference external files outside the repo
   - All context needed is inline or in INFRASTRUCTURE.md
   - Works on any machine after cloning the repo

4. **Validate frontmatter**
   ```bash
   # Ensure YAML is valid
   head -5 .claude/skills/your-skill/SKILL.md | grep -E "^(name|description):"
   ```

### Validation Checklist

Before opening a PR:

- [ ] Skill name matches directory name (kebab-case)
- [ ] Description is specific (triggers correct scenarios)
- [ ] All AWS CLI commands include `--region us-west-2`
- [ ] No `--profile` flags in any command
- [ ] All shell commands are single-line (no backslash continuations)
- [ ] Code blocks have language hints (bash, json, yaml, etc.)
- [ ] Output format example included
- [ ] Integration section links related skills
- [ ] Tested via `/reload-plugins` + `/<skill-name>` invocation
- [ ] README.md updated with new skill in appropriate category

## Contributing Workflow

### 1. Branch Naming

```
feat/aws-rds-rightsizing    # New skill
fix/aws-cost-review         # Bug fix in existing skill
docs/infrastructure-update  # Documentation only
```

### 2. Commit Message Format

```
Add aws-rds-rightsizing skill for database cost optimization

- Checks CPU/memory utilization over 14 days
- Recommends instance class downgrades
- Calculates monthly savings per recommendation
- Integrates with /aws-cost-review and /aws-reserved-capacity
```

### 3. Pull Request Template

```markdown
## Skill Overview

**Name:** `aws-rds-rightsizing`
**Category:** Cost Management
**Trigger:** "righsize RDS", "RDS cost optimization", `/aws-rds-rightsizing`

## What It Does

3-sentence summary of the skill's workflow and output.

## Testing

- [x] Tested via `/reload-plugins` + `/<skill-name>`
- [x] All AWS CLI commands validated against real account
- [x] Output format example included in SKILL.md
- [x] README.md updated

## Integration

Links to related skills:
- Triggered after `/aws-cost-review` identifies high RDS costs
- Feeds into `/aws-reserved-capacity` for RI purchase decisions
```

### 4. Review Criteria

PRs are approved when:
- Skill follows all authoring conventions above
- All AWS CLI commands are single-line with explicit `--region`
- Output format example is clear and realistic
- Integration section links related skills
- README.md updated in correct category
- Tested in real Claude Code session (screenshot or transcript excerpt)

## Repository Structure

```
devops-skills/
├── .claude/
│   └── skills/
│       ├── aws-cost-review/
│       │   └── SKILL.md
│       ├── aws-reserved-capacity/
│       │   └── SKILL.md
│       └── ... (all skills)
├── .gitignore
├── CLAUDE.md              # This file
├── INFRASTRUCTURE.md      # ClubReady AWS architecture reference
├── LICENSE
└── README.md             # User-facing documentation
```

## Skill Categories

Organize skills in README.md under these categories:

- **Cost Management** — Budget analysis, RI optimization, waste identification
- **Security & Compliance** — IAM audits, encryption checks, credentials rotation
- **Multi-Account & IaC** — AWS Organizations, Terraform, OIDC setup
- **Infrastructure Monitoring** — Health checks, performance reviews, alerting
- **Operational Runbooks** — Incident response, failover procedures, rollbacks

## Maintenance

### Quarterly Review Cycle

Every quarter (Jan, Apr, Jul, Oct):

1. **Test all skills** against current AWS API (commands may have changed)
2. **Update INFRASTRUCTURE.md** with current account IDs, costs, architecture
3. **Audit skill relevance** — archive obsolete skills, split overly-broad skills
4. **Check integrations** — ensure skill cross-references are still valid

### When AWS CLI Changes

If AWS introduces breaking CLI changes:

1. Update affected skills immediately
2. Add deprecation notice if old command still works
3. Create GitHub issue tracking migration timeline
4. Update all code examples in one PR (don't leave partial migration)

### Version Strategy

This repo does NOT use semantic versioning. Skills evolve continuously:

- **Breaking changes:** Add migration notes in skill header, keep old command commented out
- **Additions:** Just add the new skill, update README.md
- **Deprecations:** Move skill to `archive/` directory, add redirect in README.md

Users clone the repo fresh or pull latest — no version pinning.

## Philosophy

### Prefer Executable Over Prose

❌ Bad: "Check RDS CPU utilization in CloudWatch and identify over-provisioned instances"  
✅ Good: Provide the exact `aws cloudwatch get-metric-statistics` command with all parameters

### Self-Contained, Not DRY

Each skill should be **independently usable**. Don't extract common bash functions into separate files — inline them. A user should be able to read one SKILL.md and execute it without jumping to other files.

Duplication across skills is acceptable. Maintainability comes from **conventions** (this file), not code reuse.

### Output Format is Part of the Skill

Every skill should produce **structured output** (not just raw AWS CLI JSON). Show the user what "good" looks like with a realistic example in the Output Format section.

### Progressive Disclosure

Start simple, add depth:
1. Core workflow (numbered steps)
2. Output format example
3. Advanced options / edge cases
4. Integration with other skills
5. Troubleshooting (if needed)

Most users will stop after step 2. Power users read the whole thing.

## Anti-Patterns

### ❌ Don't Make Skills Interactive

Skills should be **runnable as a script** (copy-paste each command). Don't write:

```markdown
1. Run this command and note the output
2. Based on the output, decide whether to run A or B
3. If you chose A, then...
```

Instead, show both paths clearly:

```markdown
1. Check condition: `aws rds describe-db-instances ...`
2. **If Multi-AZ = false:** Run `aws rds modify-db-instance --multi-az ...`
3. **If Multi-AZ = true:** Skip to step 4
```

### ❌ Don't Assume Context

Every skill should work in a fresh terminal. Don't write:

```markdown
3. Using the CLUSTER_ID from step 1, run...
```

Instead:

```markdown
3. Get cluster ID and check backups:
   ```bash
   CLUSTER_ID=$(aws rds describe-db-clusters --region us-west-2 --query 'DBClusters[0].DBClusterIdentifier' --output text)
   aws rds describe-db-clusters --region us-west-2 --db-cluster-identifier "$CLUSTER_ID" | jq -r '.DBClusters[0].BackupRetentionPeriod'
   ```
```

### ❌ Don't Create Mega-Skills

If a skill exceeds ~500 lines or covers >5 distinct workflows, split it. Better to have:
- `aws-rds-cost-analysis`
- `aws-rds-security-audit`
- `aws-rds-performance-tuning`

Than one massive `aws-rds-everything` skill.

## Getting Help

- **Skill not triggering?** Check `description:` frontmatter — it guides the Skill tool's matching
- **AWS CLI errors?** Verify IAM permissions, region, and account ID in command
- **Command output differs?** AWS CLI output format may have changed — update skill
- **Integration unclear?** Add an Integration section linking related skills

For questions or issues:
- **Internal:** #cloud-infra-team Slack
- **External:** https://github.com/ClubReadyAWSDevOps/devops-skills/issues

## References

- [AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [INFRASTRUCTURE.md](INFRASTRUCTURE.md) — ClubReady AWS architecture details
