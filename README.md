# Voice of Customer (VoC) Translation & Sentiment Pipeline

## 1. Project Overview

**Goal:** Build a production-style Data Engineering platform that ingests multilingual Amazon customer reviews, detects language, translates non-English reviews to English when needed, performs sentiment analysis, stores curated data for analytics, and demonstrates CI/CD, orchestration, data quality, observability, and cloud cost control.

**Dataset:** `amazon_reviews_multilingual_US_v1_00.tsv` from Kaggle (approximately 3.63 GB).

> ⚠️ **Dataset Verification — Required Before Phase 3:**
> The `US` portion of the Amazon multilingual collection is predominantly English. Before building the NLP pipeline, sample ~1,000 records and run language detection to measure the actual non-English ratio. If the result shows insufficient multilingual content to demonstrate the pipeline meaningfully, supplement with one or more additional datasets:
>
> - `amazon_reviews_multilingual_DE_v1_00` (German)
> - `amazon_reviews_multilingual_FR_v1_00` (French)
> - `amazon_reviews_multilingual_JP_v1_00` (Japanese)
>
> The ingestion schema and ETL logic are identical across all these files — only the source path changes. Merge them at the Bronze layer under a shared `source_dataset` metadata column.

**Core principle:** Use AWS where it provides meaningful value, but keep expensive/always-on compute local. The recommended architecture is hybrid: **S3 + AWS NLP + Athena/Glue Catalog on AWS; Airflow + Spark locally in Docker.**

---

## 2. Target Architecture

```text
Kaggle Dataset
      |
      v
Local Ingestion (Python/CLI)
      |
      v
+------------------------------+
|            Amazon S3         |
|                              |
| raw -> bronze -> silver      |
|                    -> gold   |
+---------------+--------------+
                |
                v
        Airflow (Docker)
                |
      +---------+----------+
      |         |          |
      v         v          v
    Spark     Quality      NLP
    Local    Validation   Pipeline
                           |
                    (see Section 6
                    for detailed flow)
                           |
                           v
                   Silver NLP Parquet
                           |
                           v
                     Glue Data Catalog
                           |
                           v
                        Athena
                           |
                           v
                    Analytics / BI
```

> The NLP Pipeline is sequential, not parallel: Language Detection → (optional) Translation → Sentiment Analysis. See **Section 6** for the complete branching logic.

---

## 3. Technology Stack

| Layer | Technology |
|---|---|
| Source | Kaggle Amazon Reviews |
| Data Lake | Amazon S3 |
| Data Format | Parquet |
| ETL | Apache Spark |
| Orchestration | Apache Airflow |
| Airflow Runtime | Docker Compose |
| Language Detection | `langdetect` (local Python library) |
| Translation | AWS Translate |
| Sentiment | AWS Comprehend |
| Metadata | AWS Glue Data Catalog |
| Query | Amazon Athena |
| Data Quality | Great Expectations / custom checks |
| Local SQL | DuckDB |
| CI/CD | GitHub Actions |
| IaC | Terraform |
| Containerization | Docker |
| Authentication | GitHub OIDC + AWS IAM Role |
| Secrets | AWS Secrets Manager / local `.env` |
| Monitoring | Airflow logs + CloudWatch |
| BI | Power BI / Tableau / QuickSight (optional) |

---

## 4. AWS vs Local Decision

| Component | Decision | Reason |
|---|---|---|
| S3 | AWS | Central cloud data lake and portfolio value |
| Translate | AWS | Core cloud NLP integration |
| Comprehend | AWS | Core cloud sentiment integration |
| Athena | AWS | Serverless SQL over S3 |
| Glue Catalog | AWS | Metadata/schema for Athena |
| IAM / CloudWatch / Budget | AWS | Security and operations |
| Spark ETL | Local | Avoid unnecessary cloud compute cost |
| Airflow | Local Docker | Avoid MWAA cost |
| PostgreSQL for Airflow metadata | Local Docker | No need for RDS |
| Redis (Celery if used) | Local Docker | Avoid managed infrastructure |
| EMR / Glue ETL | Not used initially | Overkill for personal project |
| MWAA | Not used | Continuous managed orchestration is unnecessary |
| Redshift | Not used | Athena + S3 is sufficient |
| EC2 / ECS / Fargate | Not used | No always-on server required |
| SageMaker Endpoint | Not used | No persistent inference endpoint needed |
| Bedrock | Not used initially | Adds complexity/cost without improving core DE story |

---

## 4.1 Spark–S3 Connectivity Requirements

Running Spark locally (in Docker) while reading and writing to Amazon S3 requires explicit configuration. This is one of the most common failure points in hybrid local/cloud setups and must be verified independently in **Phase 1** before any ETL job is written.

### Required JARs

Spark communicates with S3 via the `s3a://` filesystem connector. The following JARs must be present in the Spark classpath, with **matching versions**:

```text
hadoop-aws-<version>.jar
aws-java-sdk-bundle-<version>.jar
```

Version mismatches between these two JARs are the primary cause of `ClassNotFoundException` and `NoSuchMethodError` at runtime. The JAR versions must match the Hadoop version bundled in the Spark distribution being used.

Example for Spark 3.4.x (Hadoop 3.3.x):

```text
hadoop-aws-3.3.4.jar
aws-java-sdk-bundle-1.12.262.jar
```

Place both JARs under `$SPARK_HOME/jars/` or pass them via `--jars` at spark-submit time.

### SparkSession Configuration

```python
spark = SparkSession.builder \
    .appName("voc-pipeline") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.aws.credentials.provider",
            "com.amazonaws.auth.EnvironmentVariableCredentialsProvider") \
    .config("spark.hadoop.fs.s3a.endpoint", "s3.amazonaws.com") \
    .config("spark.hadoop.fs.s3a.path.style.access", "false") \
    .getOrCreate()
```

### Credentials in Docker

Spark and Airflow both run inside Docker containers. AWS credentials must be injected at runtime — do **not** bake them into the image.

Two options:

**Option A — Environment variables (recommended for local dev):**

```yaml
# docker-compose.yml
environment:
  - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
  - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
  - AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
```

Load from a local `.env` file (not committed to git).

**Option B — Mount AWS credentials file:**

```yaml
volumes:
  - ~/.aws:/home/airflow/.aws:ro
```

Use a named profile and set `AWS_PROFILE` in the container environment.

### Phase 1 Smoke Test

Before writing any pipeline code, validate the Spark–S3 connection with a minimal script:

```python
df = spark.read.text("s3a://voc-analytics-dev/raw/test.txt")
df.write.mode("overwrite").parquet("s3a://voc-analytics-dev/test_output/")
```

If this fails, resolve the JAR and credential issues before proceeding to Phase 4.

---

## 5. Data Lake Design

S3 bucket example:

```text
s3://voc-analytics-dev/

raw/
  amazon_reviews/
    multilingual_us/
    multilingual_de/        ← added if supplemental datasets are used
    multilingual_jp/

bronze/
  reviews/
    ingestion_date=YYYY-MM-DD/

silver/
  reviews/
    year=YYYY/
    month=MM/

silver_nlp/
  reviews/
    year=YYYY/
    month=MM/

gold/
  customer_voice/
    year=YYYY/
    month=MM/
  product_sentiment/
    year=YYYY/
    month=MM/
  category_sentiment/

quality/
manifests/
  nlp_tracking/            ← idempotency tracking for NLP processing
logs/
```

> **Partition consistency:** Both `silver/` and `silver_nlp/` are partitioned by `year/month`. This makes the LEFT JOIN in the Gold build step straightforward and enables consistent Athena partition pruning across both layers. Language is stored as a **column** within the data, not as a partition key.

### Raw

- Preserve original source data without transformations.
- Store ingestion metadata: source, file, timestamp, size, checksum, pipeline version.

### Bronze

Semi-processed, schema-controlled Parquet.

Suggested columns:

```text
review_id
customer_id
product_id
product_parent
marketplace
product_title
product_category
star_rating
helpful_votes
total_votes
vine
verified_purchase
review_headline
review_body
review_date
source_dataset              ← which source file/country dataset this came from
_ingestion_timestamp
_source_file
_pipeline_version
```

### Silver

Cleaned and standardized data.

Derived fields can include:

```text
review_text
review_length
review_word_count
helpful_ratio
rating_group
```

Keep `star_rating` separate from NLP sentiment: rating is customer-provided feedback, while sentiment is a model prediction.

### Silver NLP

NLP-enriched layer, joined with Silver to produce Gold. Contains one row per review that has been processed through the NLP pipeline.

```text
review_id                   ← join key to silver
nlp_key                     ← SHA256(review_id + original_text + source_language)
original_text
source_language
translated_text             ← NULL if translation was skipped
translation_status          ← success | skipped_english | skipped_native | failed
translation_provider
translation_timestamp
sentiment_label
positive_score
negative_score
neutral_score
mixed_score
sentiment_model
sentiment_timestamp
processing_status           ← success | failed
```

### Gold

Business-ready analytical models. See Section 21 for full schema.

---

## 6. NLP Pipeline

```text
review_text
   |
   v
Language Detection
(local: langdetect library)
   |
   +--> English ────────────────────────────────────────────────────+
   |                                                                |
   +--> Comprehend-native language ─────────────────────────────────+
   |    (ar, zh, zh-TW, fr, de, hi, it, ja, ko, pt, es)            |
   |    → translation_status = skipped_native                       |
   |                                                                |
   +--> Other language ──→ AWS Translate ──────────────────────────+
                           → translated_text stored               |
                           → translation_status = success         |
                                                                   |
                                                            review_text_for_sentiment
                                                            (original_text if English/native,
                                                             translated_text otherwise)
                                                                   |
                                                                   v
                                                           AWS Comprehend
                                                           (BatchDetectSentiment)
                                                                   |
                                                                   v
                                                 POSITIVE / NEGATIVE / NEUTRAL / MIXED
                                                                   |
                                                                   v
                                                            Silver NLP Parquet
```

### Language Detection

Use `langdetect` (Python) as the default local implementation. It is lightweight, requires no external call, and sufficient for most review text lengths.

```python
from langdetect import detect
language_code = detect(review_text)   # returns ISO 639-1 code, e.g. 'en', 'de', 'ja'
```

For higher accuracy on very short texts (< 20 words), consider replacing with **FastText** language identification (`fasttext` + `lid.176.bin` model), which handles short strings more reliably. Keep the implementation behind a provider interface (see Section 9) so this substitution requires no changes to calling code.

### Translation Decision Logic

```text
IF source_language == 'en':
    translated_text = NULL
    translation_status = 'skipped_english'

ELSE IF source_language IN comprehend_native_languages:
    translated_text = NULL
    translation_status = 'skipped_native'

ELSE:
    translated_text = aws_translate(original_text, target='en')
    translation_status = 'success' | 'failed'
```

AWS Comprehend native sentiment languages (as of current documentation):
`ar, zh, zh-TW, en, fr, de, hi, it, ja, ko, pt, es`

Verify this list against the [AWS Comprehend documentation](https://docs.aws.amazon.com/comprehend/latest/dg/supported-languages.html) before implementation, as supported languages may expand over time.

### Sentiment

Use `BatchDetectSentiment` (up to 25 documents per call) instead of per-record API calls. This reduces the number of API round-trips and is more efficient at scale.

```python
response = comprehend.batch_detect_sentiment(
    TextList=[review["review_text_for_sentiment"] for review in batch],
    LanguageCode=language_code   # 'en' for translated, original code for native
)
```

Persist per review:

```text
sentiment_label
positive_score
negative_score
neutral_score
mixed_score
sentiment_model
sentiment_timestamp
```

---

## 7. NLP Cost Strategy

**Do not send the entire 3.63 GB dataset directly to AWS NLP services.** Translation and Comprehend costs depend on processed character volume.

Recommended execution strategy:

```text
Full dataset
   |
   v
Full ingestion + cleaning + Parquet
   |
   v
Bounded NLP subset / configurable batch
   |
   +--> 1K reviews (MVP)
   +--> 10K
   +--> 50K
   +--> larger runs when budget allows
```

### Cost Reduction via Native Language Support

By routing Comprehend-native languages (fr, de, ja, ko, es, pt, etc.) directly to Comprehend without translating first, the project avoids AWS Translate charges for those languages. This can significantly reduce cost when the dataset contains high volumes of Spanish, French, German, Japanese, Korean, or Portuguese reviews.

### Use Batch API for Comprehend

Always use `BatchDetectSentiment` (25 documents per call) rather than `DetectSentiment` (1 document per call). For 10,000 reviews, this reduces API calls from 10,000 to 400 — lowering latency and avoiding per-request overhead.

### Configurable Cost Guard

```yaml
nlp:
  translation:
    enabled: true
    max_characters: 2000000
  sentiment:
    enabled: true
    max_characters: 5000000
  max_reviews_per_run: 10000
```

Before processing, estimate characters and stop the run when the configured limit is exceeded.

---

## 8. Idempotency

Use `review_id` as the business key and calculate a deterministic NLP key:

```text
nlp_key = SHA256(review_id + original_text + source_language)
```

### Tracking Storage

Processed records are tracked in a dedicated Parquet dataset on S3:

```text
s3://voc-analytics-dev/manifests/nlp_tracking/
  year=YYYY/
  month=MM/
```

Schema:

```text
nlp_key              ← SHA256 hash (primary lookup key)
review_id
processing_status    ← success | failed
processed_at
pipeline_run_id
```

At the start of each NLP batch run, load the tracking dataset into a set (or DuckDB in-memory table) for O(1) lookup:

```python
processed_keys = set(
    duckdb.query("SELECT nlp_key FROM read_parquet('s3a://voc-analytics-dev/manifests/nlp_tracking/**/*.parquet')")
    .df()["nlp_key"]
    .tolist()
)
```

Processing logic:

```text
For each review in batch:
  IF nlp_key IN processed_keys:
    skip (already processed)
  ELSE:
    process -> persist to silver_nlp -> append nlp_key to tracking dataset
```

This prevents Airflow retries or reruns from causing duplicate translation/sentiment calls and unnecessary AWS spend.

---

## 9. NLP Provider Abstraction

Do not couple business logic directly to AWS SDK calls.

Use interfaces such as:

```text
LanguageDetectionProvider
  |- LangdetectProvider (default)
  |- FasttextProvider (higher accuracy alternative)

TranslationProvider
  |- AWSTranslateProvider
  |- LocalTranslationProvider (optional)

SentimentProvider
  |- AWSComprehendProvider (BatchDetectSentiment)
  |- LocalSentimentProvider (optional)
```

Benefits:

- Easier testing.
- Local fallback.
- Cost-control experimentation.
- Easier migration to other NLP providers.
- Swap language detection library without changing pipeline code.

---

## 10. Airflow Design

Run Airflow locally with Docker Compose rather than MWAA.

Suggested DAG/task structure:

```text
VOC Pipeline
|
+-- ingestion
|    +-- check_source
|    +-- upload_raw
|    +-- register_metadata
|
+-- transformation
|    +-- spark_bronze
|    +-- spark_silver
|    +-- data_quality
|
+-- nlp
|    +-- load_nlp_tracking        ← load processed_keys from manifests/nlp_tracking/
|    +-- language_detection
|    +-- translation
|    +-- sentiment
|    +-- update_nlp_tracking      ← append newly processed nlp_keys to tracking dataset
|
+-- gold
     +-- build_gold               ← LEFT JOIN silver + silver_nlp on review_id
     +-- repair_athena_partitions ← MSCK REPAIR TABLE for new partitions
     +-- final_quality_check
```

For a larger implementation, split into multiple DAGs:

```text
voc_ingestion_dag
voc_transform_dag
voc_nlp_dag
voc_gold_dag
```

### Gold Build Logic (`build_gold`)

The Gold layer is produced by a LEFT JOIN between `silver` and `silver_nlp` on `review_id`:

```sql
SELECT
    s.*,
    n.source_language,
    n.translated_text,
    n.translation_status,
    n.sentiment_label,
    n.positive_score,
    n.negative_score,
    n.neutral_score,
    n.mixed_score,
    CASE WHEN n.review_id IS NOT NULL THEN 'nlp_complete' ELSE 'nlp_pending' END AS nlp_status
FROM silver s
LEFT JOIN silver_nlp n ON s.review_id = n.review_id
```

Reviews without a matching `silver_nlp` record (not yet processed by the NLP pipeline) are included in Gold with NULL sentiment fields and `nlp_status = 'nlp_pending'`. This allows the Gold layer to reflect full review volume while accurately representing NLP coverage.

### Athena Partition Registration (`repair_athena_partitions`)

Glue table schemas are provisioned by Terraform (Phase 2). After each Gold run adds new partitions, the DAG runs:

```sql
MSCK REPAIR TABLE gold.fact_customer_review;
MSCK REPAIR TABLE gold.fact_product_sentiment;
```

This is a free Athena operation that discovers and registers new partition paths without requiring a Glue Crawler (which incurs additional cost).

Use Airflow retries, timeouts, task-level logging, and explicit failure states.

---

## 11. Retry and Failure Handling

Classify failures as:

```text
success
retryable_failure
permanent_failure
```

For external APIs:

```text
request
  |
  +--> success
  |
  +--> retryable failure
          |
          +--> exponential backoff
          +--> retry 1
          +--> retry 2
          +--> retry 3
          +--> failure -> S3 failure/DLQ dataset
```

Store:

```text
processing_status
error_code
error_message
attempt_count
```

Use S3 for failed-record storage instead of introducing SQS unless there is a real asynchronous messaging requirement.

---

## 12. Data Quality

Recommended checks:

### Completeness

```text
review_id IS NOT NULL
product_id IS NOT NULL
review_date IS NOT NULL
```

### Uniqueness

```text
COUNT(review_id) = COUNT(DISTINCT review_id)
```

### Validity

```text
star_rating BETWEEN 1 AND 5
helpful_votes >= 0
total_votes >= 0
helpful_votes <= total_votes
```

### NLP Quality

```text
translation_status IN ('success', 'skipped_english', 'skipped_native', 'failed')
sentiment_label IN ('POSITIVE', 'NEGATIVE', 'NEUTRAL', 'MIXED')
```

### Coverage Check

Track and alert when NLP coverage drops below a threshold:

```text
nlp_coverage_rate = COUNT(nlp_status='nlp_complete') / COUNT(*) > 0.95
```

Use Great Expectations or a focused custom validation package.

---

## 13. Analytics Layer

Use Athena over partitioned/compressed Parquet.

Example questions:

- Which product categories have the highest negative sentiment?
- Which products receive the most negative feedback?
- How does sentiment differ between verified and non-verified purchases?
- How strongly does star rating correlate with NLP sentiment?
- Which languages/categories have the highest negative-feedback rate?
- Which reviews have rating/sentiment disagreement?
- How does sentiment trend month-over-month for a given product or category?

Example gold metrics:

```text
review_count
avg_rating
positive_reviews
negative_reviews
neutral_reviews
mixed_reviews
positive_rate
negative_rate
avg_helpful_ratio
```

---

## 14. Partitioning and Performance

Prefer partitioning by:

```text
year
month
```

Apply this scheme consistently across `silver/`, `silver_nlp/`, and `gold/` to enable partition pruning for both individual layer queries and cross-layer joins.

Avoid high-cardinality partitions such as `customer_id` or `language`.

Store analytical data as compressed Parquet to reduce Athena scan volume.

Do not over-partition small datasets.

---

## 15. Repository Structure

```text
voc-pipeline/
|
+-- dags/
+-- src/
|   +-- ingestion/
|   +-- transformation/
|   +-- nlp/
|   |   +-- detection/
|   |   +-- translation/
|   |   +-- sentiment/
|   |   +-- tracking/        ← idempotency tracking logic
|   +-- quality/
|   +-- common/
|
+-- spark/
|   +-- bronze/
|   +-- silver/
|   +-- gold/
|
+-- sql/
|   +-- athena/
|   +-- analytics/
|
+-- tests/
+-- terraform/
+-- docker/
+-- configs/
+-- scripts/
+-- docs/
|
+-- docker-compose.yml
+-- requirements.txt
+-- pyproject.toml
+-- Makefile
+-- README.md
```

---

## 16. Configuration

Avoid hard-coding operational settings. Use YAML/environment-based configuration.

Example:

```yaml
environment: dev

source:
  name: amazon_reviews
  files:
    - amazon_reviews_multilingual_US_v1_00.tsv
    - amazon_reviews_multilingual_DE_v1_00.tsv  # add if supplemental datasets are used

storage:
  bucket: voc-analytics-dev

processing:
  partition_by:
    - year
    - month

nlp:
  language_detection:
    provider: langdetect          # or: fasttext

  translation:
    enabled: true
    provider: aws_translate
    max_characters: 2000000
    skip_comprehend_native: true  # skip translate for Comprehend-supported languages

  sentiment:
    enabled: true
    provider: aws_comprehend
    max_characters: 5000000
    batch_size: 25                # BatchDetectSentiment limit

  max_reviews_per_run: 10000
```

---

## 17. CI/CD

### Pull Request CI

Run:

```text
ruff
black --check
mypy
pytest
SQLFluff
Terraform fmt
Terraform validate
Airflow DAG import tests
Docker build test
```

### CD on main

```text
merge to main
   |
   v
build
   |
   v
test
   |
   v
terraform plan
   |
   v
terraform apply
```

Use **GitHub Actions OIDC + AWS IAM role** instead of storing long-lived AWS access keys.

> **Note:** For a personal project, auto-applying on merge to main is acceptable. For a production-style setup, add a manual approval gate between `terraform plan` and `terraform apply` using GitHub Actions `environment: production` with required reviewers.

---

## 18. Infrastructure as Code

Use Terraform.

```text
terraform/
|
+-- modules/
|   +-- s3/
|   +-- iam/
|   +-- athena/
|   +-- glue_catalog/
|   +-- cloudwatch/
|
+-- environments/
    +-- dev/
    +-- prod/
```

Terraform provisions:
- S3 bucket and folder structure
- IAM roles and policies
- Glue Data Catalog databases and table schemas
- Athena workgroup and output location
- CloudWatch log groups and alarms
- AWS Budgets alerts

Expected commands:

```text
terraform fmt
terraform validate
terraform plan
terraform apply
terraform destroy
```

> Glue table schemas are created by Terraform. Partition registration at runtime is handled by `MSCK REPAIR TABLE` in Athena (see Section 10) — no Glue Crawler is required.

---

## 19. Observability

Capture pipeline metrics:

```text
run_id
dag_id
start_time
end_time
status
input_records
output_records
failed_records
translation_records
sentiment_records
skipped_english_records
skipped_native_records
translation_characters
sentiment_characters
estimated_aws_cost
```

Example run log:

```text
records_read=150000
records_cleaned=149321
records_invalid=679
translation_candidates=31245
skipped_english=118076
skipped_native=5420
translated=25825
translation_chars=1982345
sentiment_candidates=149321
sentiment_chars=4991221
comprehend_api_calls=5973          ← 149321 / 25 (batch size)
estimated_cost=<value>
status=success
```

Use Airflow logs locally and CloudWatch for AWS-side operational visibility.

---

## 20. AWS Cost Control

### Main cost-sensitive services

- AWS Translate: character-based pricing.
- AWS Comprehend: character/unit-based pricing.
- Athena: data scanned.
- S3: storage/requests.

### Controls

- Limit NLP characters per run via configurable guard.
- Route Comprehend-native languages directly to sentiment — skip Translate.
- Use `BatchDetectSentiment` (25 docs/call) to minimize API overhead.
- Use idempotent NLP processing to prevent duplicate calls on retries.
- Persist intermediate NLP results.
- Use Parquet + compression + year/month partitioning for Athena scan reduction.
- Add AWS Budget alerts.
- Destroy unused infrastructure.
- Keep Spark and Airflow local.

---

## 21. Gold Data Model

### `fact_customer_review`

```text
review_id
customer_id
product_id
review_date
star_rating
original_text
translated_text             ← NULL if English or Comprehend-native
source_language
translation_status          ← success | skipped_english | skipped_native | failed
sentiment_label
positive_score
negative_score
neutral_score
mixed_score
nlp_status                  ← nlp_complete | nlp_pending
verified_purchase
helpful_votes
total_votes
```

### `dim_product`

```text
product_id
product_parent
product_title
product_category
```

### `dim_date`

```text
date
year
month
quarter
day
day_of_week
week_of_year
is_weekend
```

### `fact_product_sentiment`

**Grain: one row per `(product_id, year, month)`** — enables month-over-month trend analysis.

```text
product_id
year
month
review_count
avg_rating
positive_reviews
negative_reviews
neutral_reviews
mixed_reviews
positive_rate
negative_rate
avg_helpful_ratio
```

> Without a time dimension, this table would aggregate all reviews into a single row per product, making trend analysis impossible. The `(product_id, year, month)` grain allows tracking sentiment changes over time.

---

## 22. DuckDB — Local Development Role

DuckDB serves as the local SQL engine for development and validation tasks. It is not part of the production pipeline but supports:

- **Pre-upload validation:** Query Parquet files locally before writing to S3.
- **NLP tracking lookup:** Load `manifests/nlp_tracking/` into an in-memory DuckDB table for fast idempotency checks (see Section 8).
- **Query prototyping:** Develop and test Athena SQL queries locally against Parquet samples.
- **Cost-free iteration:** Test Gold model logic locally without incurring Athena scan costs.

DuckDB can read S3 Parquet files directly via the `httpfs` extension, allowing local queries against production data when needed.

---

## 23. Implementation Roadmap

### Phase 1 — Environment

- Create GitHub repository.
- Configure Python, Docker, Spark, Airflow, AWS CLI and Terraform.
- Start Airflow with Docker Compose.
- **Validate Spark–S3 connectivity** with a minimal read/write smoke test (see Section 4.1). Do not proceed to Phase 4 until this passes.

**Deliverable:** reproducible local development environment with confirmed S3 access from Spark.

### Phase 2 — AWS Foundation

- Create S3 bucket with the full folder structure (including `manifests/nlp_tracking/`).
- Set IAM permissions.
- Configure Athena and Glue Catalog table schemas via Terraform.
- Configure AWS Budget/alerts.
- Terraform the infrastructure.

**Deliverable:** reproducible AWS foundation.

### Phase 3 — Ingestion

```text
Kaggle -> download -> checksum -> S3 raw -> metadata
```

**Pre-condition:** Before proceeding, sample the dataset and run language detection on ~1,000 records to assess non-English volume. If insufficient, add supplemental datasets at this phase.

**Deliverable:** raw source stored in S3 with lineage metadata and confirmed language distribution.

### Phase 4 — Spark ETL

```text
Raw -> Bronze -> Silver
```

**Deliverable:** cleaned, partitioned Parquet dataset in `silver/year=YYYY/month=MM/`.

### Phase 5 — Data Quality

Add schema, completeness, uniqueness, validity, and business-rule checks.

**Deliverable:** automated quality report and failing-run behavior.

### Phase 6 — Translation + Sentiment

Start with:

```text
1,000 reviews -> 10,000 -> 50,000 -> larger runs
```

Implement language detection, Comprehend-native routing, translation, batch sentiment, retries, idempotency tracking, cost controls, and provider abstraction.

**Deliverable:** enriched multilingual review dataset in `silver_nlp/year=YYYY/month=MM/`.

### Phase 7 — Analytics

Build Gold models (with time-dimensioned `fact_product_sentiment`) and Athena queries for product/category/customer-voice analysis.

**Deliverable:** business-ready analytics dataset and optional dashboard.

### Phase 8 — CI/CD + Operations

Implement GitHub Actions, OIDC, Terraform deployment, monitoring, and documentation.

**Deliverable:** reproducible production-style project.

### Phase 9 — Scale/Benchmark

- Compare cloud NLP with local NLP.
- Benchmark Spark performance.
- Measure cost per 1K / 10K / 100K reviews.
- Test full-dataset ETL.
- Document scaling from 100K to 100M reviews.

---

## 24. MVP Definition

Build this first:

```text
10,000 reviews (confirmed multilingual sample)
   |
   v
S3 Raw
   |
   v
Spark Silver
   |
   v
Language Detection (local)
   |
   +--> English / native → skip Translate
   +--> Other → AWS Translate
   |
   v
AWS Comprehend (BatchDetectSentiment)
   |
   v
Silver NLP (s3://voc-analytics-dev/silver_nlp/year=.../month=.../)
   |
   v
Build Gold (LEFT JOIN silver + silver_nlp)
   |
   v
MSCK REPAIR TABLE → Athena
```

Only after the MVP is stable should the project scale to larger datasets.

---

## 25. Production-Style Questions the Project Should Answer

The architecture should allow you to explain:

1. Why S3 instead of a database for raw/analytical storage?
2. Why Parquet instead of TSV/CSV for downstream analytics?
3. Why Airflow locally instead of MWAA?
4. Why Spark locally instead of EMR/Glue ETL?
5. How is NLP API cost controlled?
6. How is the pipeline idempotent? Where is processing state stored?
7. What happens when AWS Translate or Comprehend fails?
8. How are failed records recovered?
9. How would you scale from 100K to 100M reviews?
10. How would you migrate local Spark jobs to AWS Glue?
11. How do partitioning and compression reduce Athena scan costs?
12. How do GitHub Actions and OIDC securely deploy to AWS?
13. How do you separate customer rating from model-predicted sentiment?
14. How do you detect data-quality regressions?
15. Why are some non-English reviews not translated before sentiment analysis?
16. How does the Gold layer handle reviews that have not yet been through the NLP pipeline?
17. How did you configure Spark to read and write S3 from a local Docker environment?

---

## 26. Suggested Portfolio/CV Positioning

### Project title

**Voice of Customer Translation & Sentiment Data Platform**

### Example CV bullets

- Built a production-style multilingual Voice of Customer data platform using Apache Spark, Airflow, Amazon S3, Athena, AWS Translate and Amazon Comprehend to automate review ingestion, language-aware translation routing, and batch sentiment enrichment.
- Implemented a medallion-style data lake (raw → bronze → silver → silver_nlp → gold) with consistent year/month partitioned Parquet on Amazon S3 for scalable analytical workloads and cost-efficient Athena queries.
- Implemented idempotent, cost-aware NLP processing with SHA256-keyed tracking on S3, configurable character limits, Comprehend-native language routing, batch API calls, and provider abstraction to control AWS Translate and Comprehend usage.
- Automated infrastructure provisioning and CI/CD using Terraform, GitHub Actions, and GitHub OIDC with automated testing, DAG validation, and deployment workflows.

---

## 27. Final Architecture Decision

The recommended personal-project architecture is:

```text
AWS
|
+-- S3                  <- central data lake
+-- Translate           <- translation (non-English, non-Comprehend-native only)
+-- Comprehend          <- sentiment (BatchDetectSentiment)
+-- Glue Data Catalog   <- metadata / table schemas (Terraform-managed)
+-- Athena              <- SQL analytics (MSCK REPAIR TABLE for partitions)
+-- IAM                 <- security
+-- CloudWatch          <- AWS-side monitoring
+-- Budgets             <- cost alerts

LOCAL / DOCKER
|
+-- Airflow             <- orchestration
+-- Spark               <- ETL (s3a:// connector to S3)
+-- PostgreSQL          <- Airflow metadata DB
+-- Redis (optional)    <- Celery executor
+-- DuckDB              <- local dev / validation / idempotency tracking

GITHUB
|
+-- GitHub Actions      <- CI/CD
+-- OIDC                <- secure AWS authentication

IAC
|
+-- Terraform           <- infrastructure provisioning
```

---

## 28. Guiding Principle

> **Use AWS for managed capabilities that add clear architectural value; keep continuous or compute-heavy workloads local when the economics do not justify managed cloud services.**

The most important engineering themes of this project are not the number of AWS services used, but **data lineage, reproducibility, idempotency, quality, failure handling, cost awareness, scalability, and operational readiness**.
