"""
Pytest configuration and shared fixtures for VOC Pipeline tests.
"""
from __future__ import annotations

import os
import pytest
import boto3
from moto import mock_aws


@pytest.fixture(scope="session", autouse=True)
def aws_mock_env():
    """Set fake AWS credentials for all tests (moto)."""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "ap-southeast-1"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"


@pytest.fixture
def s3_bucket(aws_mock_env):
    """Create a mock S3 bucket for tests."""
    with mock_aws():
        s3 = boto3.client("s3", region_name="ap-southeast-1")
        s3.create_bucket(
            Bucket="voc-analytics-dev",
            CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"},
        )
        yield s3
