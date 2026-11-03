output "s3_bucket_name" {
  description = "S3 data lake bucket."
  value       = module.data_lake.bucket_name
}

output "s3_bucket_arn" {
  description = "S3 data lake bucket ARN."
  value       = module.data_lake.bucket_arn
}

output "glue_database_name" {
  description = "Glue Data Catalog database."
  value       = aws_glue_catalog_database.reviews.name
}

output "glue_table_names" {
  description = "Glue Catalog tables provisioned for the VoC data lake."
  value       = { for key, table in aws_glue_catalog_table.reviews : key => table.name }
}

output "athena_workgroup_name" {
  description = "Athena query workgroup with enforced scan limit."
  value       = aws_athena_workgroup.reviews.name
}

output "pipeline_access_policy_arn" {
  description = "Attach this managed IAM policy to the local development IAM role/user used by boto3."
  value       = aws_iam_policy.pipeline_access.arn
}

output "monthly_budget_created" {
  description = "Whether the optional monthly budget alert was created."
  value       = length(aws_budgets_budget.monthly) > 0
}
