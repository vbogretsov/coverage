variable "region" {
  type        = "string"
  description = "AWS region where resources will be created."
}

variable "name" {
  type        = "string"
  description = "Coverage server name."
  default     = "coverage"
}

variable "domain" {
  type        = "string"
  description = "Root domain name."
}

variable "certificate_arn" {
  type        = "string"
  description = "ARN of ACM certificate located in region us-east-1. Certificate must be valid for 'var.name.var.domain' domain name."
}
