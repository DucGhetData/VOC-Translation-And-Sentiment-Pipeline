"""
VOC Pipeline — Common utilities: logging, config, S3 client factory
"""
from __future__ import annotations

import hashlib
import os
from functools import lru_cache
from pathlib import Path

import boto3
import yaml
from loguru import logger


# ── Logging setup ─────────────────────────────────────────────────────────────
def setup_logger(level: str = "INFO") -> None:
    """Configure loguru with a structured format."""
    logger.remove()
    logger.add(
        sink=lambda msg: print(msg, end=""),
        level=level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level:<8}</level> | <cyan>{name}</cyan>:<cyan>{line}</cyan> — {message}",
        colorize=True,
    )


# ── Config loader ─────────────────────────────────────────────────────────────
@lru_cache(maxsize=1)
def load_config(config_path: str | None = None) -> dict:
    """Load pipeline.yaml config. Cached after first load."""
    if config_path is None:
        root = Path(__file__).parents[2]
        config_path = str(root / "configs" / "pipeline.yaml")

    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ── S3 client factory ─────────────────────────────────────────────────────────
def get_s3_client():
    """Return a boto3 S3 client using env credentials."""
    return boto3.client(
        "s3",
        region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-1"),
    )


def get_s3_resource():
    """Return a boto3 S3 resource (for higher-level operations)."""
    return boto3.resource(
        "s3",
        region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-1"),
    )


# ── NLP key generation ────────────────────────────────────────────────────────
def make_nlp_key(review_id: str, original_text: str, source_language: str) -> str:
    """
    Generate a deterministic SHA256 key for idempotency tracking.

    nlp_key = SHA256(review_id + original_text + source_language)
    """
    content = f"{review_id}|{original_text}|{source_language}"
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


# ── S3 path helpers ───────────────────────────────────────────────────────────
def s3_path(bucket: str, *parts: str) -> str:
    """Build an s3:// path from parts."""
    key = "/".join(p.strip("/") for p in parts if p)
    return f"s3://{bucket}/{key}"


def s3_key(*parts: str) -> str:
    """Build an S3 key (no bucket prefix) from parts."""
    return "/".join(p.strip("/") for p in parts if p)
