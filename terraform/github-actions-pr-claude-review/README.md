# GitHub Actions PR Claude review role (PIQ)

Least-privilege OIDC role in account `397665031723` for `PerformanceIQ/booking-system` to invoke Anthropic models on Bedrock. Distinct from `github-actions-claude-review` (devops-skills monthly audits) and `gh-actions-deploy` (ECR/ECS).

```bash
aws sts get-caller-identity --profile piq   # expect 397665031723
tofu init
tofu apply -var profile=piq
```

State: local `terraform.tfstate` (gitignored). The shared `cr-tf-backend` bucket requires profile `sa-cr`; switch the backend later if that SSO session is available.
