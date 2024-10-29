###############################################
# Terraform remote backend in Terraform Cloud #
###############################################

terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "Tech-blog"

    workspaces {
      name = "Tech-blog-CT"
    }
  }
}

# Provider

provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "n-virginia"
}

#############
# Variables #
#############

variable "domain_name" {
  description = "The domain name of my blog"
  type = string
  default = "paul-test-projects.co.uk"
}

###############################################
# Bucket for our static website configuration #
###############################################

# Bucket config

resource "aws_s3_bucket" "tech_blog" {
  bucket = "paul-tech-blog-ct"

  tags = {
    Name        = "My bucket"
  }
}

# Static website config

resource "aws_s3_bucket_website_configuration" "static_website" {
  bucket = aws_s3_bucket.tech_blog.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Public access config

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.tech_blog.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy config

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.tech_blog.id
  policy = data.aws_iam_policy_document.allow_public_access.json
}

data "aws_iam_policy_document" "allow_public_access" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [ "s3:GetObject" ]

    resources = [ "${aws_s3_bucket.tech_blog.arn}/*" ]
  }
}

###############################
# R53 and Certificate Manager #
###############################

resource "aws_route53_zone" "zone" {
  name = var.domain_name
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  provider = aws.n-virginia

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id = aws_route53_zone.zone.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 60
  records = [each.value.resource_record_value]
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn = aws_acm_certificate.cert.arn
  provider = aws.n-virginia

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation : record.fqdn
  ]

   depends_on = [aws_route53_record.cert_validation]
}


##############
# CloudFront #
##############

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "movies-oac"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  origin_access_control_origin_type = "s3"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.tech_blog.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "myS3Origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Managed by Terraform"
  default_root_object = "index.html"

  aliases = ["www.${var.domain_name}", "${var.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "myS3Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  depends_on = [aws_acm_certificate_validation.cert_validation]
}

resource "aws_route53_record" "records_for_cf" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }

  depends_on = [ aws_cloudfront_distribution.s3_distribution ]
}

resource "aws_route53_record" "records_for_cf_www" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }

  depends_on = [ aws_cloudfront_distribution.s3_distribution ]
}

###########
# Outputs #
###########

output "CF_Distribution" {
  value = aws_cloudfront_distribution.s3_distribution.id
}

output "CF_Name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "S3_Name" {
  value = aws_s3_bucket.tech_blog.id
}

