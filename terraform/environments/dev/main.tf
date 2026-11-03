data "aws_caller_identity" "current" {}

module "data_lake" {
  source      = "../../modules/s3"
  bucket_name = var.bucket_name
  tags = {
    DataClassification = "customer-reviews"
  }
}

resource "aws_glue_catalog_database" "reviews" {
  name        = var.glue_database_name
  description = "Glue catalog for the VoC review data lake (${var.environment})."
}

locals {
  glue_tables = {
    bronze_reviews = {
      location = "bronze/reviews/"
      columns = [
        { name = "review_id", type = "string" },
        { name = "customer_id", type = "string" },
        { name = "product_id", type = "string" },
        { name = "product_parent", type = "string" },
        { name = "marketplace", type = "string" },
        { name = "product_title", type = "string" },
        { name = "product_category", type = "string" },
        { name = "star_rating", type = "int" },
        { name = "helpful_votes", type = "int" },
        { name = "total_votes", type = "int" },
        { name = "vine", type = "boolean" },
        { name = "verified_purchase", type = "boolean" },
        { name = "review_headline", type = "string" },
        { name = "review_body", type = "string" },
        { name = "review_date", type = "date" },
        { name = "source_dataset", type = "string" },
        { name = "_ingestion_timestamp", type = "timestamp" },
        { name = "_source_file", type = "string" },
        { name = "_pipeline_version", type = "string" },
      ]
      partition_keys = [{ name = "ingestion_date", type = "string" }]
    }
    silver_reviews = {
      location = "silver/reviews/"
      columns = [
        { name = "review_id", type = "string" },
        { name = "customer_id", type = "string" },
        { name = "product_id", type = "string" },
        { name = "product_parent", type = "string" },
        { name = "marketplace", type = "string" },
        { name = "product_title", type = "string" },
        { name = "product_category", type = "string" },
        { name = "star_rating", type = "int" },
        { name = "helpful_votes", type = "int" },
        { name = "total_votes", type = "int" },
        { name = "vine", type = "boolean" },
        { name = "verified_purchase", type = "boolean" },
        { name = "review_text", type = "string" },
        { name = "review_date", type = "date" },
        { name = "source_dataset", type = "string" },
        { name = "review_length", type = "int" },
        { name = "review_word_count", type = "int" },
        { name = "helpful_ratio", type = "double" },
        { name = "rating_group", type = "string" },
        { name = "_ingestion_timestamp", type = "timestamp" },
        { name = "_source_file", type = "string" },
        { name = "_pipeline_version", type = "string" },
      ]
      partition_keys = [
        { name = "year", type = "int" },
        { name = "month", type = "int" },
      ]
    }
    silver_nlp_reviews = {
      location = "silver_nlp/reviews/"
      columns = [
        { name = "review_id", type = "string" },
        { name = "nlp_key", type = "string" },
        { name = "original_text", type = "string" },
        { name = "source_language", type = "string" },
        { name = "translated_text", type = "string" },
        { name = "translation_status", type = "string" },
        { name = "translation_provider", type = "string" },
        { name = "translation_timestamp", type = "timestamp" },
        { name = "sentiment_label", type = "string" },
        { name = "positive_score", type = "double" },
        { name = "negative_score", type = "double" },
        { name = "neutral_score", type = "double" },
        { name = "mixed_score", type = "double" },
        { name = "sentiment_model", type = "string" },
        { name = "sentiment_timestamp", type = "timestamp" },
        { name = "processing_status", type = "string" },
      ]
      partition_keys = [
        { name = "year", type = "int" },
        { name = "month", type = "int" },
      ]
    }
    fact_customer_review = {
      location = "gold/customer_voice/"
      columns = [
        { name = "review_id", type = "string" },
        { name = "customer_id", type = "string" },
        { name = "product_id", type = "string" },
        { name = "review_date", type = "date" },
        { name = "star_rating", type = "int" },
        { name = "original_text", type = "string" },
        { name = "translated_text", type = "string" },
        { name = "source_language", type = "string" },
        { name = "translation_status", type = "string" },
        { name = "sentiment_label", type = "string" },
        { name = "positive_score", type = "double" },
        { name = "negative_score", type = "double" },
        { name = "neutral_score", type = "double" },
        { name = "mixed_score", type = "double" },
        { name = "nlp_status", type = "string" },
        { name = "verified_purchase", type = "boolean" },
        { name = "helpful_votes", type = "int" },
        { name = "total_votes", type = "int" },
      ]
      partition_keys = [
        { name = "year", type = "int" },
        { name = "month", type = "int" },
      ]
    }
    dim_product = {
      location = "gold/dim_product/"
      columns = [
        { name = "product_id", type = "string" },
        { name = "product_parent", type = "string" },
        { name = "product_title", type = "string" },
        { name = "product_category", type = "string" },
      ]
      partition_keys = []
    }
    dim_date = {
      location = "gold/dim_date/"
      columns = [
        { name = "date", type = "date" },
        { name = "year", type = "int" },
        { name = "month", type = "int" },
        { name = "quarter", type = "int" },
        { name = "day", type = "int" },
        { name = "day_of_week", type = "string" },
        { name = "week_of_year", type = "int" },
        { name = "is_weekend", type = "boolean" },
      ]
      partition_keys = []
    }
    fact_product_sentiment = {
      location = "gold/product_sentiment/"
      columns = [
        { name = "product_id", type = "string" },
        { name = "review_count", type = "bigint" },
        { name = "avg_rating", type = "double" },
        { name = "positive_reviews", type = "bigint" },
        { name = "negative_reviews", type = "bigint" },
        { name = "neutral_reviews", type = "bigint" },
        { name = "mixed_reviews", type = "bigint" },
        { name = "positive_rate", type = "double" },
        { name = "negative_rate", type = "double" },
        { name = "avg_helpful_ratio", type = "double" },
      ]
      partition_keys = [
        { name = "year", type = "int" },
        { name = "month", type = "int" },
      ]
    }
  }
}

resource "aws_glue_catalog_table" "reviews" {
  for_each = local.glue_tables

  name          = each.key
  database_name = aws_glue_catalog_database.reviews.name
  description   = "${replace(each.key, "_", " ")} table for the VoC ${var.environment} data lake."
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    classification        = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  dynamic "partition_keys" {
    for_each = each.value.partition_keys
    content {
      name = partition_keys.value.name
      type = partition_keys.value.type
    }
  }

  storage_descriptor {
    location      = "s3://${module.data_lake.bucket_name}/${each.value.location}"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    dynamic "columns" {
      for_each = each.value.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }

    ser_de_info {
      name                  = "${each.key}_serde"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
  }
}

resource "aws_athena_workgroup" "reviews" {
  name        = var.athena_workgroup_name
  description = "Cost-controlled Athena workgroup for VoC development queries."
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${module.data_lake.bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

data "aws_iam_policy_document" "pipeline_access" {
  statement {
    sid       = "ListDataLakeBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [module.data_lake.bucket_arn]
  }

  statement {
    sid    = "ReadWriteDataLakeObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${module.data_lake.bucket_arn}/*"]
  }

  statement {
    sid    = "UseGlueCatalog"
    effect = "Allow"
    actions = [
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:CreateTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdateTable",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.reviews.name}",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.reviews.name}/*",
    ]
  }

  statement {
    sid    = "RunAthenaQueries"
    effect = "Allow"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
    ]
    resources = [aws_athena_workgroup.reviews.arn]
  }
}

resource "aws_iam_policy" "pipeline_access" {
  name        = "${var.project_name}-${var.environment}-pipeline-access"
  description = "S3, Glue Catalog, and Athena access for the VoC pipeline. Attach to the local development role/user."
  policy      = data.aws_iam_policy_document.pipeline_access.json
}

resource "aws_budgets_budget" "monthly" {
  count = var.budget_alert_email == "" ? 0 : 1

  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
