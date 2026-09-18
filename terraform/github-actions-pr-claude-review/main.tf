provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

# Bedrock invoke only. Inline policy so later ARN tweaks use PutRolePolicy
# (PIQ SCP p-079vx2qq denies iam:CreatePolicyVersion on managed policies).
data "aws_iam_policy_document" "bedrock" {
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.*",
      "arn:aws:bedrock:*:*:inference-profile/us.anthropic.*",
    ]
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "GitHub Actions OIDC: Bedrock invoke for PerformanceIQ/booking-system PR review (no ECS/ECR/audit)."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Purpose   = "github-actions-pr-claude-review"
  })

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.account_id
      error_message = "Refusing to create this role outside account ${var.account_id} (got ${data.aws_caller_identity.current.account_id}). Use profile piq."
    }
  }
}

resource "aws_iam_role_policy" "bedrock" {
  name   = "bedrock-invoke-anthropic"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.bedrock.json
}
