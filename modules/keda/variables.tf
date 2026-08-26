###############################################################################
# Inputs for the KEDA AWS-side prerequisites. The in-cluster install
# (HelmRelease, ScaledObjects, TriggerAuthentications) lives in gitops-flux;
# this module only creates what has to exist in AWS: the operator IRSA role and
# a read-only policy for the AWS trigger sources KEDA is allowed to poll.
###############################################################################

variable "cluster_name" {
  description = "EKS cluster name. Used in the IAM role name so roles stay identifiable per cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider. The federated principal in the operator role's trust policy."
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

variable "namespace" {
  description = "Namespace the KEDA operator runs in. Half of the IRSA trust condition's service-account subject."
  type        = string
  default     = "keda"
}

variable "service_account" {
  description = "ServiceAccount the KEDA operator runs as. Must match serviceAccount.operator.name in the gitops-flux HelmRelease - note the KEDA chart nests this under `operator`, and an annotation placed at serviceAccount.annotations instead is silently ignored."
  type        = string
  default     = "keda-operator"
}

variable "queue_name_prefixes" {
  description = "SQS queue name prefixes KEDA may read attributes from. Deliberately excludes the platform queues: `u25c-shared` is Karpenter's interruption queue and KEDA has no business reading it."
  type        = list(string)
  default     = ["u25c-dev-*", "u25c-stage-*", "u25c-prod-*"]
}
