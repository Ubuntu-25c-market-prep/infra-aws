###############################################################################
# Inputs for the Karpenter AWS-side prerequisites. The in-cluster install
# (Helm release, NodePool, EC2NodeClass) lives in gitops-flux; this module only
# creates what has to exist in AWS: the controller IRSA role, the node role and
# its cluster access entry, the interruption SQS queue with its EventBridge
# rules, and the karpenter.sh/discovery tags the EC2NodeClass selects on.
###############################################################################

variable "cluster_name" {
  description = "EKS cluster name. Used in resource names, the IRSA trust condition and every tag/ARN scoping condition in the controller policy."
  type        = string
}

variable "region" {
  description = "Region the cluster runs in. Scopes the controller policy's regional read actions and SSM/ARN paths."
  type        = string
}

variable "account_id" {
  description = "Workload AWS account id. Scopes the instance-profile and EKS ARNs in the controller policy."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (module.eks.oidc_provider_arn). The federated principal in the controller role's trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix (module.eks.oidc_provider_url). Used to build the sub/aud trust conditions."
  type        = string
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary attached to both IAM roles this module creates. Required when a PlatformEngineer applies - that permission set only allows creating roles that carry the engineer boundary. null when an admin/CI applies."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets Karpenter launches nodes into. Tagged with karpenter.sh/discovery=<cluster_name> so the EC2NodeClass can select them by tag."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "The worker node security group (module.eks.node_security_group_id). Tagged for discovery so Karpenter nodes get the same node-to-node / control-plane rules the managed node group uses."
  type        = string
}

variable "cluster_security_group_id" {
  description = "The EKS-managed cluster security group (module.eks.cluster_security_group_id). Tagged for discovery and selected alongside the node SG, mirroring the managed node group's launch template."
  type        = string
}

variable "karpenter_namespace" {
  description = "Namespace the Karpenter controller runs in. Half of the IRSA trust condition's service-account subject."
  type        = string
  default     = "karpenter"
}

variable "karpenter_service_account" {
  description = "ServiceAccount name the Karpenter controller uses. Must match the Helm release's serviceAccount.name. The other half of the IRSA trust subject."
  type        = string
  default     = "karpenter"
}
