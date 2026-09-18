variable "region" {
  description = "AWS region for the provider (IAM is global; Bedrock resources are region-wildcarded)."
  type        = string
  default     = "us-west-2"
}

variable "profile" {
  description = "AWS CLI/SSO profile for the PIQ account (piq, or sa-piq if present)."
  type        = string
  default     = "piq"
}

variable "account_id" {
  description = "Expected AWS account. Apply aborts if the profile is in a different account."
  type        = string
  default     = "397665031723"
}

variable "role_name" {
  type    = string
  default = "github-actions-pr-claude-review"
}

variable "github_repo" {
  description = "GitHub org/name allowed to assume this role via OIDC (ref wildcarded)."
  type        = string
  default     = "PerformanceIQ/booking-system"
}

variable "tags" {
  type    = map(string)
  default = {}
}
