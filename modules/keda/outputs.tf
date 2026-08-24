output "operator_role_arn" {
  description = "IRSA role ARN for the KEDA operator. Annotate the Helm serviceAccount.operator with eks.amazonaws.com/role-arn = this."
  value       = aws_iam_role.operator.arn
}
