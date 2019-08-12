terraform {
  required_version = ">= 0.12"

  backend "s3" {
  }
}

provider "aws" {
  region = var.region
}

locals {
  origin_id = "${var.name}-s3origin"
  domain    = "${var.name}.${var.domain}"
}

data "aws_route53_zone" "zone" {
  name         = "${var.domain}."
  private_zone = false
}

data "aws_iam_policy_document" "reporters" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.reports.arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.reports.arn}/*"
    ]

    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.identity.iam_arn,
      ]
    }
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.reports.arn
    ]

    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.identity.iam_arn
      ]
    }
  }
}

data "template_file" "credentials" {
  template = file("credentials")

  vars = {
    id     = aws_iam_access_key.reporter_key.id
    secret = aws_iam_access_key.reporter_key.secret
  }
}

resource "local_file" "credentials" {
  content  = data.template_file.credentials.rendered
  filename = ".credentials"
}

resource "aws_iam_group" "reporters" {
  name = "${var.name}-reporters"
}

resource "aws_iam_group_policy" "reporters" {
  name   = "reporters"
  group  = aws_iam_group.reporters.id
  policy = data.aws_iam_policy_document.reporters.json
}

resource "aws_iam_user" "reporter" {
  name = "${var.name}-reporter"
}

resource "aws_iam_access_key" "reporter_key" {
  user = aws_iam_user.reporter.name
}

resource "aws_iam_user_group_membership" "membership" {
  user = aws_iam_user.reporter.name

  groups = [
    aws_iam_group.reporters.name,
  ]
}

resource "aws_s3_bucket" "reports" {
  bucket = "${replace("${var.name}-reports-${var.domain}", ".", "-")}"
  acl    = "private"
}

resource "aws_s3_bucket_policy" "reports" {
  bucket = aws_s3_bucket.reports.id
  policy = data.aws_iam_policy_document.bucket.json
}

resource "aws_cloudfront_origin_access_identity" "identity" {
  comment = "S3 reports bucket access identity"
}

resource "aws_cloudfront_distribution" "reports" {
  enabled = true

  aliases = [
    local.domain,
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.origin_id}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
    compress    = true

    viewer_protocol_policy = "allow-all"
  }

  origin {
    domain_name = aws_s3_bucket.reports.bucket_regional_domain_name
    origin_id   = local.origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.identity.cloudfront_access_identity_path
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_route53_record" "alias" {
  zone_id = data.aws_route53_zone.zone.id
  name    = var.name
  type    = "CNAME"
  ttl     = 60

  records = [
    aws_cloudfront_distribution.reports.domain_name
  ]
}
