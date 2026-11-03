"""
Unit tests for common utilities: NLP key generation, S3 path helpers.
"""
from __future__ import annotations

import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parents[3] / "src"))

from common.utils import make_nlp_key, s3_path, s3_key


class TestMakeNlpKey:
    def test_returns_sha256_hex(self):
        key = make_nlp_key("R001", "Great product!", "en")
        assert len(key) == 64
        assert all(c in "0123456789abcdef" for c in key)

    def test_deterministic(self):
        key1 = make_nlp_key("R001", "Great product!", "en")
        key2 = make_nlp_key("R001", "Great product!", "en")
        assert key1 == key2

    def test_different_inputs_different_keys(self):
        key1 = make_nlp_key("R001", "Great product!", "en")
        key2 = make_nlp_key("R002", "Great product!", "en")
        assert key1 != key2

    def test_language_affects_key(self):
        key_en = make_nlp_key("R001", "Great product!", "en")
        key_de = make_nlp_key("R001", "Great product!", "de")
        assert key_en != key_de


class TestS3Helpers:
    def test_s3_path(self):
        result = s3_path("voc-analytics-dev", "silver", "reviews")
        assert result == "s3://voc-analytics-dev/silver/reviews"

    def test_s3_path_strips_slashes(self):
        result = s3_path("voc-analytics-dev", "/silver/", "/reviews/")
        assert result == "s3://voc-analytics-dev/silver/reviews"

    def test_s3_key(self):
        result = s3_key("silver", "reviews", "year=2024")
        assert result == "silver/reviews/year=2024"
