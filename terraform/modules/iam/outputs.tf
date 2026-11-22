output "group_names" {
  value = local.groups
}

output "enforce_mfa_policy_arn" {
  value = aws_iam_policy.enforce_mfa.arn
}

output "region_restrict_policy_arn" {
  value = aws_iam_policy.region_restrict.arn
}
