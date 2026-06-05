locals {
  oidc_host              = replace(var.oidc_issuer_url, "https://", "")
  controller_sa_name     = "aws-load-balancer-controller"
  controller_namespace   = "kube-system"
  # The controller runs in kube-system by convention — it is cluster infrastructure,
  # not application code. Keeping it separate from application namespaces also
  # means RBAC policies for app namespaces do not accidentally affect it.
}

# ── Trust policy ──────────────────────────────────────────────────────────────
# Same IRSA pattern as the app role, but scoped to the controller's service account
# in kube-system instead of the app service account in gitflow-analyzer.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${local.controller_namespace}:${local.controller_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ── Controller IAM role ───────────────────────────────────────────────────────
resource "aws_iam_role" "lb_controller" {
  name               = "${var.project}-${var.env}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── Controller IAM policy ─────────────────────────────────────────────────────
# The controller calls EC2 and ELB APIs to create and manage ALBs on your behalf.
# Each statement group below maps to a specific controller action.
data "aws_iam_policy_document" "lb_controller" {

  # Read VPC topology so the controller can choose the right subnets for the ALB
  statement {
    sid    = "ReadNetworkTopology"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
    ]
    resources = ["*"]
    # EC2 describe actions cannot be scoped to specific resources — AWS requires *.
  }

  # Manage security groups for the ALB
  # The controller creates a dedicated SG for each ALB and attaches it to nodes
  statement {
    sid    = "ManageSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TagSecurityGroupsAndENIs"
    effect = "Allow"
    actions = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = [
      "arn:aws:ec2:*:*:security-group/*",
      "arn:aws:ec2:*:*:network-interface/*",
    ]
  }

  # Create and manage the actual load balancers, listeners, rules, and target groups
  statement {
    sid    = "ManageLoadBalancers"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]
  }

  # Read ACM certificates to attach to HTTPS listeners
  statement {
    sid    = "ReadCertificates"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:GetCertificate",
    ]
    resources = ["*"]
  }

  # Create the ELB service-linked role on first use in the account
  statement {
    sid     = "CreateELBServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
      # Prevents this permission from being used to create service-linked roles
      # for any other AWS service — scoped to ELB only.
    }
  }

  # Read server certificates stored in IAM (legacy HTTPS — most people use ACM)
  statement {
    sid    = "ReadIAMCertificates"
    effect = "Allow"
    actions = [
      "iam:GetServerCertificate",
      "iam:ListServerCertificates",
    ]
    resources = ["*"]
  }

  # Associate WAF web ACLs with ALBs for WAF-based rate limiting or IP blocking
  statement {
    sid    = "ManageWAF"
    effect = "Allow"
    actions = [
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "waf:GetWebACL",
    ]
    resources = ["*"]
  }

  # Read Cognito user pools for ALB authentication actions
  statement {
    sid     = "ReadCognito"
    effect  = "Allow"
    actions = ["cognito-idp:DescribeUserPoolClient"]
    resources = ["*"]
  }

  # Check Shield subscription so the controller can protect ALBs if Shield Advanced is enabled
  statement {
    sid    = "ReadShield"
    effect = "Allow"
    actions = [
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.project}-${var.env}-lb-controller"
  policy = data.aws_iam_policy_document.lb_controller.json

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ── Helm release ──────────────────────────────────────────────────────────────
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = local.controller_namespace

  set {
    name  = "clusterName"
    value = var.cluster_name
    # The controller uses this to filter Ingress resources — it only manages
    # Ingresses in the cluster it is installed in.
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
    # The controller needs the VPC ID to create the ALB in the right VPC and
    # to look up available subnets.
  }

  set {
    name  = "serviceAccount.name"
    value = local.controller_sa_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lb_controller.arn
    # This annotation is how IRSA works on the Kubernetes side.
    # The EKS pod identity webhook sees this annotation and injects the
    # AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE env vars into the pod.
    # The AWS SDK then uses those to exchange the OIDC token for credentials.
  }

  depends_on = [aws_iam_role_policy_attachment.lb_controller]
  # The IAM role must have its policy attached before the controller starts,
  # otherwise it launches but immediately fails all API calls.
}
