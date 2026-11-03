variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "tags" {
  description = "Additional tags for the bucket."
  type        = map(string)
  default     = {}
}
