###############################################################################
# Inputs for the cert-manager AWS-side prerequisites. The in-cluster install
# (HelmRelease, ClusterIssuer, Certificate) lives in gitops-flux; this module
# only creates what has to exist in AWS: the controller IRSA role and a
# Route 53 policy scoped to one hosted zone.
###############################################################################

variable "cluster_name" {
  description = "EKS cluster name. Used in the IAM role name so roles stay identifiable per cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider. The federated principal in the controller role's trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix. Used to build the sub/aud trust conditions."
  type        = string
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary attached to the IAM role. Required when a PlatformEngineer applies - that permission set only allows creating roles that carry the engineer boundary. null when an admin/CI applies."
  type        = string
  default     = null
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone cert-manager may write DNS-01 challenge records into. The ChangeResourceRecordSets statement is scoped to this zone alone."
  type        = string
}

variable "namespace" {
  description = "Namespace the cert-manager controller runs in. Half of the IRSA trust condition's service-account subject."
  type        = string
  default     = "cert-manager"
}

variable "service_account" {
  description = "ServiceAccount name the controller uses. The other half of the trust subject; must match serviceAccount.name in the gitops-flux HelmRelease."
  type        = string
  default     = "cert-manager"
}