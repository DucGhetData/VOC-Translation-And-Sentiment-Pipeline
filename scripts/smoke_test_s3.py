#!/usr/bin/env python3
"""
Phase 1 Smoke Test — Python–S3 Connectivity
============================================
Run this script BEFORE writing any pipeline code to validate that:
  1. boto3 can authenticate with AWS
  2. S3 read/write works from your local environment
  3. Parquet upload/download via pyarrow works correctly

Usage:
    python scripts/smoke_test_s3.py

Prerequisites:
    - .env file with AWS credentials (copy from .env.example)
    - venv activated with requirements installed
    - S3 bucket already created (Phase 2 prerequisite, or create manually first)
"""

import os
import sys
from io import BytesIO
from datetime import datetime, timezone

# Load .env before importing boto3
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    print("⚠️  python-dotenv not installed — reading env vars directly from shell")

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from botocore.exceptions import ClientError, NoCredentialsError


# ── Config ────────────────────────────────────────────────────────────────────
BUCKET = os.environ.get("S3_BUCKET", "voc-analytics-dev")
REGION = os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-1")
TEST_PREFIX = "smoke_test"
TIMESTAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def separator(title: str) -> None:
    print(f"\n{'─' * 55}")
    print(f"  {title}")
    print(f"{'─' * 55}")


def test_credentials() -> bool:
    """Verify AWS credentials are valid via STS GetCallerIdentity."""
    separator("1. Verifying AWS Credentials")
    try:
        sts = boto3.client("sts", region_name=REGION)
        identity = sts.get_caller_identity()
        print(f"  ✅ Account  : {identity['Account']}")
        print(f"  ✅ UserID   : {identity['UserId']}")
        print(f"  ✅ ARN      : {identity['Arn']}")
        return True
    except NoCredentialsError:
        print("  ❌ No credentials found. Check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in .env")
        return False
    except ClientError as e:
        print(f"  ❌ Credential error: {e}")
        return False


def test_s3_text_roundtrip(s3) -> bool:
    """Upload a text file to S3 and read it back."""
    separator("2. S3 Text Read/Write Roundtrip")
    key = f"{TEST_PREFIX}/test_{TIMESTAMP}.txt"
    content = b"hello from voc-pipeline smoke test"

    try:
        # Write
        s3.put_object(Bucket=BUCKET, Key=key, Body=content)
        print(f"  ✅ Uploaded : s3://{BUCKET}/{key}")

        # Read back
        obj = s3.get_object(Bucket=BUCKET, Key=key)
        result = obj["Body"].read()
        assert result == content, f"Content mismatch: {result!r} != {content!r}"
        print(f"  ✅ Read back: '{result.decode()}'")

        # Cleanup
        s3.delete_object(Bucket=BUCKET, Key=key)
        print(f"  ✅ Cleaned up test object")
        return True
    except ClientError as e:
        print(f"  ❌ S3 error: {e}")
        return False


def test_s3_parquet_roundtrip(s3) -> bool:
    """Upload a sample Parquet file to S3 and read it back via pyarrow."""
    separator("3. S3 Parquet Read/Write Roundtrip (pyarrow)")
    key = f"{TEST_PREFIX}/test_{TIMESTAMP}.parquet"

    # Create sample DataFrame
    df_original = pd.DataFrame({
        "review_id": ["R001", "R002", "R003"],
        "star_rating": [5, 3, 1],
        "review_body": ["Great product!", "It's okay.", "Terrible, avoid."],
        "language": ["en", "fr", "de"],
        "_test_timestamp": [TIMESTAMP] * 3,
    })

    try:
        # Write Parquet to buffer → upload to S3
        buffer = BytesIO()
        df_original.to_parquet(buffer, index=False, engine="pyarrow")
        buffer.seek(0)
        s3.put_object(Bucket=BUCKET, Key=key, Body=buffer.getvalue())
        print(f"  ✅ Uploaded Parquet : s3://{BUCKET}/{key}")
        print(f"  ✅ Shape            : {df_original.shape} (rows, cols)")

        # Read back from S3 → DataFrame
        obj = s3.get_object(Bucket=BUCKET, Key=key)
        df_read = pd.read_parquet(BytesIO(obj["Body"].read()), engine="pyarrow")
        assert df_read.shape == df_original.shape, "Shape mismatch after roundtrip"
        assert list(df_read.columns) == list(df_original.columns), "Columns mismatch"
        print(f"  ✅ Read back shape  : {df_read.shape} — matches ✓")

        # Cleanup
        s3.delete_object(Bucket=BUCKET, Key=key)
        print(f"  ✅ Cleaned up test object")
        return True
    except ClientError as e:
        print(f"  ❌ S3 error: {e}")
        return False
    except Exception as e:
        print(f"  ❌ Parquet error: {e}")
        return False


def test_s3_list_bucket(s3) -> bool:
    """Verify bucket exists and is accessible."""
    separator("4. Verify Bucket Access")
    try:
        response = s3.head_bucket(Bucket=BUCKET)
        print(f"  ✅ Bucket '{BUCKET}' exists and is accessible")
        return True
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "404":
            print(f"  ⚠️  Bucket '{BUCKET}' does not exist yet — create it in Phase 2 (Terraform)")
            print(f"       This is OK for Phase 1 connectivity check. Skipping Parquet tests.")
        elif error_code == "403":
            print(f"  ❌ Access denied to bucket '{BUCKET}' — check IAM permissions")
        else:
            print(f"  ❌ Bucket error ({error_code}): {e}")
        return False


def main() -> int:
    print("\n╔══════════════════════════════════════════════════════╗")
    print("║  VOC Pipeline — Phase 1 Smoke Test (Python–S3)      ║")
    print(f"║  Timestamp: {TIMESTAMP:<40}║")
    print("╚══════════════════════════════════════════════════════╝")

    results: dict[str, bool] = {}

    # Test 1: Credentials
    results["credentials"] = test_credentials()
    if not results["credentials"]:
        print("\n❌ Credentials failed — cannot proceed with S3 tests")
        return 1

    # Initialise S3 client
    s3 = boto3.client("s3", region_name=REGION)

    # Test 2: Bucket access
    bucket_ok = test_s3_list_bucket(s3)
    results["bucket_access"] = bucket_ok

    if bucket_ok:
        # Test 3: Text roundtrip
        results["s3_text_roundtrip"] = test_s3_text_roundtrip(s3)

        # Test 4: Parquet roundtrip
        results["s3_parquet_roundtrip"] = test_s3_parquet_roundtrip(s3)
    else:
        results["s3_text_roundtrip"] = False
        results["s3_parquet_roundtrip"] = False

    # ── Summary ────────────────────────────────────────────────────────────────
    separator("Summary")
    all_passed = True
    for name, passed in results.items():
        icon = "✅" if passed else "❌"
        status = "PASS" if passed else "FAIL"
        print(f"  {icon}  {name:<30} {status}")
        if not passed:
            all_passed = False

    if all_passed:
        print("\n🎉 All smoke tests passed! Ready to proceed to Phase 2.\n")
        return 0
    elif results["credentials"] and not bucket_ok:
        print("\n⚠️  AWS credentials OK. Bucket not found — create it in Phase 2 (Terraform).")
        print("   Phase 1 connectivity is confirmed. Proceed.\n")
        return 0
    else:
        print("\n❌ Some tests failed. Resolve issues before proceeding to Phase 4.\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
