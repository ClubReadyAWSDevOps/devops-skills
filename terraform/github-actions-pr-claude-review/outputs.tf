output "role_arn" {
  description = "ARN to set as GitHub Actions variable CLAUDE_REVIEW_ROLE_ARN on PerformanceIQ/booking-system."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "trusted_repo" {
  value = var.github_repo
}
