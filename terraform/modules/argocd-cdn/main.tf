terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
      # CloudFront certificates must live in us-east-1 — AWS hard requirement.
      # The us_east_1 alias is passed in from the calling environment.
    }
  }
}

# ── ACM certificate ───────────────────────────────────────────────────────────
# Covers argocd.gitflow.space only. Must be in us-east-1 for CloudFront.
# After apply, Terraform outputs the DNS validation CNAME — add it to GoDaddy
# and ACM will validate automatically within ~5 minutes.

resource "aws_acm_certificate" "argocd" {
  provider          = aws.us_east_1
  domain_name       = var.argocd_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project     = var.project
    Environment = var.env
    Name        = "${var.project}-${var.env}-argocd-cert"
  }
}

resource "aws_acm_certificate_validation" "argocd" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.argocd.arn
  # Blocks until ACM confirms DNS ownership. Add the CNAME record from the
  # argocd_acm_validation_record output to GoDaddy before this times out.
}

# ── CloudFront distribution ───────────────────────────────────────────────────
# Dedicated distribution for argocd.gitflow.space. Routes to the shared ALB —
# the ALB uses the Host header to match the ArgoCD Ingress rule.

resource "aws_cloudfront_distribution" "argocd" {
  enabled     = true
  price_class = "PriceClass_100"
  aliases     = [var.argocd_hostname]
  comment     = "${var.project}-${var.env} argocd"

  origin {
    origin_id   = "alb-argocd"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      # ALB listens on HTTP/80. TLS terminates here at CloudFront.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-argocd"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # CachingDisabled — ArgoCD UI responses must never be cached.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # AllViewer — forwards the original Host header (argocd.gitflow.space) to
    # the ALB so its Ingress host rule can match and route to ArgoCD server.
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.argocd.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Project     = var.project
    Environment = var.env
    Name        = "${var.project}-${var.env}-argocd-cdn"
  }
}
