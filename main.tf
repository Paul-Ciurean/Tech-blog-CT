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

#############
# Variables #
#############

variable "aws_account_id" {
  description = "Your Account ID"
  type        = string
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

##########################################
# Cloud Front distribution configuration #
##########################################

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket_website_configuration.static_website.website_endpoint
    origin_id                = local.s3_origin_id

    # Configure as a custom origin
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Terraform"
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
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

