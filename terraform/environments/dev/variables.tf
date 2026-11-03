variable "aws_region" {
  description = "AWS region for the development data lake."
  type        = string
  default     = "ap-southeast-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for this environment."
  type        = string

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63
    error_message = "bucket_name must be between 3 and 63 characters."
  }
}

variable "project_name" {
  description = "Project tag and name prefix."
  type        = string
  default     = "voc-pipeline"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "glue_database_name" {
  description = "Glue Data Catalog database name."
  type        = string
  default     = "voc_reviews_dev"
}

variable "athena_workgroup_name" {
  description = "Athena workgroup name."
  type        = string
  default     = "voc-pipeline-dev"
}

variable "athena_bytes_scanned_cutoff" {
  description = "Maximum bytes Athena may scan in one query (1 GiB by default)."
  type        = number
  default     = 1073741824

  validation {
    condition     = var.athena_bytes_scanned_cutoff >= 10485760
    error_message = "Athena scan cutoff must be at least 10 MiB."
  }
}

variable "budget_alert_email" {
  description = "Optional email for the monthly AWS budget alert. Leave empty to skip creating a budget until configured."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly AWS budget threshold in USD."
  type        = number
  default     = 10
}
