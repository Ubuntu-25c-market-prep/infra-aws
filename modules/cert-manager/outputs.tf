output "controller_role_arn" {
  description = "IRSA role ARN for the cert-manager controller. Annotate the Helm serviceAccount with eks.amazonaws.com/role-arn = this."
  value       = aws_iam_role.controller.arn
}