#!/usr/bin/env python3
"""
ClickHouse Deduplication Test Suite - Utilities
"""

import random
import json
import time
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Tuple, Dict, Any
import clickhouse_connect

@dataclass
class TestRecord:
    timestamp: datetime
    account: str
    product: str
    metric_value: float
    metric_count: int
    category: str
    region: str
    status: str
    description: str
    extra_data: str

class DataGenerator:
    """테스트 데이터 생성"""
    CATEGORIES = ['electronics', 'clothing', 'food', 'furniture', 'sports']
    REGIONS = ['asia', 'europe', 'americas', 'oceania', 'africa']
    STATUSES = ['active', 'pending', 'completed', 'cancelled']

    def __init__(self, config):
        self.config = config
        self.base_time = datetime.now() - timedelta(hours=1)

    def generate(self) -> Tuple[List[TestRecord], int]:
        """테스트 데이터 생성 (중복 포함)"""
        print(f"데이터 생성 중: {self.config.total_unique_records} unique records...")
        unique_records = []

        for i in range(self.config.total_unique_records):
            record = TestRecord(
                timestamp=self.base_time + timedelta(milliseconds=i * 360),
                account=f'account_{random.randint(1, self.config.account_cardinality):04d}',
                product=f'product_{random.randint(1, self.config.product_cardinality):03d}',
                metric_value=round(random.random() * 10000, 2),
                metric_count=random.randint(1, 1000),
                category=random.choice(self.CATEGORIES),
                region=random.choice(self.REGIONS),
                status=random.choice(self.STATUSES),
                description=f'Record {i}',
                extra_data=json.dumps({'idx': i})
            )
            unique_records.append(record)

        # 중복 데이터 추가
        num_dup = int(len(unique_records) * self.config.duplicate_rate)
        duplicates = random.sample(unique_records, num_dup)
        all_records = unique_records + duplicates
        random.shuffle(all_records)

        print(f"✓ 총 {len(all_records)} records 생성 완료 (unique: {len(unique_records)}, duplicates: {num_dup})")
        return all_records, len(unique_records)

class ClickHouseClient:
    """ClickHouse 클라이언트 래퍼"""

    def __init__(self, config):
        self.config = config
        self.client = None
        self.connect()

    def connect(self):
        """ClickHouse 연결"""
        try:
            self.client = clickhouse_connect.get_client(
                host=self.config.host,
                port=self.config.port,
                username=self.config.username,
                password=self.config.password,
                database=self.config.database,
                secure=self.config.secure
            )
            # 연결 테스트
            result = self.client.command("SELECT 1")
            print(f"✓ ClickHouse 연결 성공: {self.config.host}")
        except Exception as e:
            print(f"✗ ClickHouse 연결 실패: {e}")
            raise

    def execute_ddl(self, ddl: str, description: str = ""):
        """DDL 실행"""
        try:
            if description:
                print(f"  {description}...")
            self.client.command(ddl)
            if description:
                print(f"  ✓ {description} 완료")
        except Exception as e:
            print(f"  ✗ {description} 실패: {e}")
            raise

    def insert_batch(self, table: str, records: List[TestRecord],
                    columns: List[str] = None) -> float:
        """배치 insert"""
        if columns is None:
            columns = ['timestamp', 'account', 'product', 'metric_value',
                      'metric_count', 'category', 'region', 'status',
                      'description', 'extra_data']

        data = [[r.timestamp, r.account, r.product, r.metric_value,
                r.metric_count, r.category, r.region, r.status,
                r.description, r.extra_data] for r in records]

        start = time.time()
        self.client.insert(table, data, column_names=columns)
        elapsed = time.time() - start
        return elapsed

    def get_count(self, table: str, use_final: bool = False) -> int:
        """레코드 수 조회"""
        query = f"SELECT count() FROM {table}"
        if use_final:
            query = f"SELECT count() FROM {table} FINAL"
        return self.client.command(query)

    def optimize_table(self, table: str):
        """테이블 최적화"""
        self.client.command(f"OPTIMIZE TABLE {table} FINAL")

    def truncate_table(self, table: str):
        """테이블 truncate"""
        try:
            self.client.command(f"TRUNCATE TABLE {table}")
        except:
            pass

def print_header(title: str):
    """헤더 출력"""
    print("\n" + "=" * 70)
    print(f"  {title}")
    print("=" * 70)

def print_results_table(headers: List[str], rows: List[List[Any]]):
    """결과 테이블 출력"""
    # 컬럼 너비 계산
    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            col_widths[i] = max(col_widths[i], len(str(cell)))

    # 헤더 출력
    header_line = " | ".join(h.ljust(w) for h, w in zip(headers, col_widths))
    print("\n" + header_line)
    print("-" * len(header_line))

    # 데이터 출력
    for row in rows:
        row_line = " | ".join(str(cell).ljust(w) for cell, w in zip(row, col_widths))
        print(row_line)
    print()
