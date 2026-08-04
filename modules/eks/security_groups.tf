###############################################################################
# Security groups for the EKS control plane and worker nodes, and the rules
# between them. IPv4 only - our VPC has no IPv6.
#
# Note there is NO ingress from 0.0.0.0/0 on the node SG: nodes accept traffic
# only from the control plane and from each other. That is the ADR 0005 rule
# "node SG denies all inbound from the internet".
###############################################################################

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_name}-node"
  }
}

resource "aws_security_group" "control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "EKS control plane"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_name}-control-plane"
  }
}

###############################################################################
# Ingress
###############################################################################

# Pods on one node talk to pods on another (and to themselves): all traffic.
resource "aws_security_group_rule" "node_to_node" {
  security_group_id = aws_security_group.node.id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Node to node"
}

# Control plane -> kubelet on 10250 (pod status, logs, kubectl exec).
resource "aws_security_group_rule" "control_plane_to_kubelet" {
  security_group_id        = aws_security_group.node.id
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  description              = "Control plane to kubelet"
}

# Control plane -> nodes on 443 (admission webhooks).
resource "aws_security_group_rule" "control_plane_to_nodes" {
  security_group_id        = aws_security_group.node.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  description              = "Control plane to nodes"
}

# Nodes -> control plane API on 443 (registration, kubelet status).
resource "aws_security_group_rule" "nodes_to_control_plane" {
  security_group_id        = aws_security_group.control_plane.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node.id
  description              = "Nodes to control plane"
}

###############################################################################
# Egress - all outbound (IPv4). Nodes need this to reach the API, ECR and S3.
###############################################################################

resource "aws_security_group_rule" "node_egress" {
  security_group_id = aws_security_group.node.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

resource "aws_security_group_rule" "control_plane_egress" {
  security_group_id = aws_security_group.control_plane.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}
