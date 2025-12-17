#!/usr/bin/env python3
"""
ClickHouse Deduplication Test Suite - Configuration
"""

import os
from dataclasses import dataclass
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

@dataclass
class TestConfig:
    host: str = os.getenv("CH_HOST", "localhost")
    port: int = int(os.getenv("CH_PORT", "8443"))
    username: str = os.getenv("CH_USERNAME", "default")
    password: str = os.getenv("CH_PASSWORD", "")
    database: str = os.getenv("CH_DATABASE", "dedup")
    secure: bool = os.getenv("CH_SECURE", "true").lower() == "true"

    # Test data configuration
    total_unique_records: int = 10000
    duplicate_rate: float = 0.3
    account_cardinality: int = 1000
    product_cardinality: int = 500
