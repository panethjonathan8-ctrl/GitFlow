terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
      # ACM certificates for CloudFront must be created in us-east-1 regardless
      # of where the rest of the infrastructure lives. The us_east_1 alias is
      # passed in from the calling environment.
    }
  }
}

data "aws_caller_identity" "current" {}

# ── ACM Certificate ───────────────────────────────────────────────────────────
# CloudFront requires the certificate to be in us-east-1 — this is an AWS
# hard requirement regardless of where your other resources live.
# The certificate covers both the apex (gitflow.space) and www subdomain.

resource "aws_acm_certificate" "cdn" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  # DNS validation: ACM gives us CNAME records to add to GoDaddy.
  # Once added, ACM verifies ownership and issues the certificate automatically.

  lifecycle {
    create_before_destroy = true
    # Ensures the new certificate is ready before the old one is removed
    # when the certificate needs to be replaced (e.g. domain name change).
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_acm_certificate_validation" "cdn" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cdn.arn
  # Blocks until ACM confirms the certificate is validated.
  # Add the CNAME records from the acm_validation_records output to GoDaddy
  # while this apply is running — validation usually completes in 2-5 minutes.
}

# ── S3 bucket ─────────────────────────────────────────────────────────────────
# Stores the static frontend files (index.html, etc.).
# Kept fully private — only CloudFront can read it via the OAC below.
# No static website hosting is needed because CloudFront serves the files.

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-frontend-${var.env}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  # All four settings enforced — objects can only be reached through CloudFront.
}

# ── CloudFront Origin Access Control ─────────────────────────────────────────
# OAC lets CloudFront sign requests to S3 with SigV4 so the bucket stays
# private. The older OAI mechanism is deprecated by AWS in favour of OAC.

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project}-${var.env}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── S3 bucket policy ──────────────────────────────────────────────────────────
# Grants CloudFront (and only this specific distribution) read access to the
# bucket. The aws:SourceArn condition prevents other distributions from
# reading your bucket even if they somehow knew the bucket name.

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

# ── CloudFront Function: strip /api prefix ────────────────────────────────────
# The browser calls /api/analyze. CloudFront matches the /api/* behaviour and
# forwards to the ALB, but result-api expects /analyze (no /api prefix).
# This function rewrites the URI before the request reaches the ALB.
# CloudFront Functions run at the edge in <1ms — no cold start, no Lambda cost.

resource "aws_cloudfront_function" "strip_api_prefix" {
  name    = "${var.project}-${var.env}-strip-api-prefix"
  runtime = "cloudfront-js-2.0"
  comment = "Strip /api prefix before forwarding to result-api"
  publish = true

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      request.uri = request.uri.replace(/^\/api/, '') || '/';
      return request;
    }
  EOF
}

# ── CloudFront distribution ───────────────────────────────────────────────────
# Two origins, two behaviours:
#   1. /api/*  → ALB (result-api) — no caching, CloudFront Function strips prefix
#   2. /*      → S3 (static files) — cached at edge, compressed

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  # PriceClass_100: US and Europe edge locations only.
  # Cheapest option — covers the likely user base for a dev environment.
  # Change to PriceClass_All for global production coverage.

  aliases = [var.domain_name, "www.${var.domain_name}"]
  # Tell CloudFront to accept requests for both the apex and www subdomain.
  # GoDaddy must have CNAME records pointing both to this distribution.

  comment = "${var.project}-${var.env} frontend"

  # ── Origin: S3 (static files) ────────────────────────────────────────────
  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
    # bucket_regional_domain_name is used instead of bucket_domain_name to
    # avoid redirects when the bucket is in a non-US region.
  }

  # ── Origin: ALB (result-api) ──────────────────────────────────────────────
  origin {
    origin_id   = "alb-result-api"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      # The ALB Ingress only listens on HTTP (port 80). HTTPS termination
      # happens at CloudFront, so this is safe — the ALB is not public-facing
      # independently.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  # ── Behaviour: /api/* → ALB ───────────────────────────────────────────────
  # Grafana has moved to its own distribution (grafana.gitflow.space) so the
  # /dashboard* behaviour is no longer needed here.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-result-api"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # CachingDisabled — API responses must never be served from cache.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # AllViewerExceptHostHeader — forwards headers, cookies, query strings
    # to the origin. Excludes Host so CloudFront replaces it with the ALB
    # hostname (required for the ALB to accept the request).
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.strip_api_prefix.arn
      # Strips /api prefix: /api/analyze → /analyze before hitting ALB.
    }
  }

  # ── Behaviour 2: /* → S3 (default) ───────────────────────────────────────
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    # compress: CloudFront gzips/brotli-compresses responses automatically.
    # The index.html is ~30 KB — compression cuts it to ~8 KB.

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # CachingOptimized — long TTLs, compression enabled. Good for static files
    # that rarely change. CI invalidates the cache on every deploy so users
    # always get the latest version after a release.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cdn.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
    # sni-only: modern browsers all support SNI — no legacy support needed.
    # TLSv1.2_2021: disables older TLS versions with known vulnerabilities.
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── SSM: persist distribution ID ─────────────────────────────────────────────
# The deploy workflow reads this instead of a hardcoded GitHub variable.
# Every terraform apply overwrites it with the current distribution ID so
# cache invalidation always targets the right distribution automatically.
resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  name  = "/${var.project}/${var.env}/cloudfront-distribution-id"
  type  = "String"
  value = aws_cloudfront_distribution.main.id

  tags = {
    Project     = var.project
    Environment = var.env
  }
}
