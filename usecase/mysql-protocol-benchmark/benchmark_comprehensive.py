#!/usr/bin/env python3
"""
Comprehensive ClickHouse Optimization Benchmark
- 원본 MergeTree (index_granularity=8192)
- 최적화 MergeTree (index_granularity=256)
- Memory 엔진
- PREWHERE 최적화
"""

import mysql.connector
from mysql.connector import pooling
import time
import random
import statistics
import concurrent.futures
from dataclasses import dataclass, field
from typing import List
import json
from datetime import datetime
import threading

@dataclass
class BenchmarkResult:
    target: str
    table_engine: str
    optimization: str
    concurrency: int
    total_queries: int
    duration_seconds: float
    successful_queries: int
    failed_queries: int
    latencies_ms: List[float] = field(default_factory=list)

    @property
    def qps(self) -> float:
        return self.successful_queries / self.duration_seconds if self.duration_seconds > 0 else 0

    @property
    def avg_latency_ms(self) -> float:
        return statistics.mean(self.latencies_ms) if self.latencies_ms else 0

    @property
    def p50_latency_ms(self) -> float:
        return statistics.median(self.latencies_ms) if self.latencies_ms else 0

    @property
    def p95_latency_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_lat = sorted(self.latencies_ms)
        return sorted_lat[int(len(sorted_lat) * 0.95)]

    @property
    def p99_latency_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_lat = sorted(self.latencies_ms)
        return sorted_lat[int(len(sorted_lat) * 0.99)]


class ComprehensiveBenchmark:
    MYSQL_CONFIG = {
        "host": "localhost",
        "port": 3306,
        "user": "testuser",
        "password": "testpass",
        "database": "gamedb",
        "autocommit": True,
    }

    CLICKHOUSE_CONFIG = {
        "host": "localhost",
        "port": 9004,
        "user": "testuser",
        "password": "testpass",
        "database": "gamedb",
        "autocommit": True,
    }

    MAX_PLAYER_ID = 2_000_000
    QUERIES_PER_WORKER = 500

    def __init__(self):
        self.results: List[BenchmarkResult] = []

    def generate_random_player_ids(self, count: int) -> List[int]:
        return [random.randint(1, self.MAX_PLAYER_ID) for _ in range(count)]

    def create_connection_pool(self, config: dict, pool_size: int):
        pool_config = config.copy()
        pool_config["pool_size"] = min(pool_size, 32)
        pool_config["pool_name"] = f"pool_{config['port']}_{pool_size}_{random.randint(1,10000)}"
        pool_config["pool_reset_session"] = False
        return pooling.MySQLConnectionPool(**pool_config)

    def execute_single_query(self, pool, player_id: int, table_name: str, use_prewhere: bool = False) -> tuple:
        where_keyword = "PREWHERE" if use_prewhere else "WHERE"
        query = f"""
            SELECT player_id, player_name, character_id, character_name,
                   character_level, character_class, server_id, server_name,
                   last_login_at, currency_gold, currency_diamond
            FROM {table_name}
            {where_keyword} player_id = {player_id}
        """

        conn = None
        try:
            start_time = time.perf_counter()
            conn = pool.get_connection()
            cursor = conn.cursor()
            cursor.execute(query)
            result = cursor.fetchall()
            cursor.close()
            end_time = time.perf_counter()

            latency_ms = (end_time - start_time) * 1000
            return (True, latency_ms, len(result))
        except Exception as e:
            return (False, 0, str(e))
        finally:
            if conn:
                conn.close()

    def worker_thread(self, pool, player_ids: List[int], table_name: str, use_prewhere: bool, results_list: list, lock: threading.Lock):
        local_latencies = []
        local_success = 0
        local_fail = 0

        for pid in player_ids:
            success, latency, _ = self.execute_single_query(pool, pid, table_name, use_prewhere)
            if success:
                local_latencies.append(latency)
                local_success += 1
            else:
                local_fail += 1

        with lock:
            results_list.extend(local_latencies)
            results_list.append(('stats', local_success, local_fail))

    def run_benchmark(self, target: str, config: dict, concurrency: int,
                     table_name: str, table_engine: str, optimization: str,
                     use_prewhere: bool = False) -> BenchmarkResult:
        print(f"\n{'='*70}")
        print(f"{target} | Engine: {table_engine} | Optimization: {optimization}")
        print(f"Concurrency: {concurrency} | Table: {table_name} | PREWHERE: {use_prewhere}")
        print(f"{'='*70}")

        pool = self.create_connection_pool(config, concurrency)

        total_queries = concurrency * self.QUERIES_PER_WORKER
        all_player_ids = self.generate_random_player_ids(total_queries)

        chunks = [
            all_player_ids[i:i + self.QUERIES_PER_WORKER]
            for i in range(0, total_queries, self.QUERIES_PER_WORKER)
        ]

        results_list = []
        lock = threading.Lock()

        # Warmup
        print("Warming up...")
        for pid in self.generate_random_player_ids(10):
            self.execute_single_query(pool, pid, table_name, use_prewhere)

        print(f"Executing {total_queries} queries...")
        start_time = time.perf_counter()

        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = [
                executor.submit(self.worker_thread, pool, chunk, table_name, use_prewhere, results_list, lock)
                for chunk in chunks
            ]
            concurrent.futures.wait(futures)

        end_time = time.perf_counter()
        duration = end_time - start_time

        latencies = [r for r in results_list if not isinstance(r, tuple)]
        stats = [r for r in results_list if isinstance(r, tuple) and r[0] == 'stats']

        total_success = sum(s[1] for s in stats)
        total_fail = sum(s[2] for s in stats)

        result = BenchmarkResult(
            target=target,
            table_engine=table_engine,
            optimization=optimization,
            concurrency=concurrency,
            total_queries=total_queries,
            duration_seconds=duration,
            successful_queries=total_success,
            failed_queries=total_fail,
            latencies_ms=latencies
        )

        self.print_result(result)
        return result

    def print_result(self, r: BenchmarkResult):
        print(f"\n--- Results ---")
        print(f"Queries: {r.successful_queries:,} / {r.total_queries:,}")
        print(f"Duration: {r.duration_seconds:.2f}s")
        print(f"QPS: {r.qps:,.2f}")
        print(f"Latency: avg={r.avg_latency_ms:.2f}ms, p50={r.p50_latency_ms:.2f}ms, p95={r.p95_latency_ms:.2f}ms, p99={r.p99_latency_ms:.2f}ms")

    def run_all_benchmarks(self, concurrency_levels: List[int] = None):
        if concurrency_levels is None:
            concurrency_levels = [8, 16, 24, 32]

        all_results = []

        for concurrency in concurrency_levels:
            # MySQL Baseline
            mysql_result = self.run_benchmark(
                "MySQL", self.MYSQL_CONFIG, concurrency,
                "player_last_login", "InnoDB", "Baseline", False
            )
            all_results.append(mysql_result)
            time.sleep(1)

            # ClickHouse 원본 (WHERE)
            ch_original_where = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login", "MergeTree", "Original-WHERE", False
            )
            all_results.append(ch_original_where)
            time.sleep(1)

            # ClickHouse 원본 (PREWHERE)
            ch_original_prewhere = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login", "MergeTree", "Original-PREWHERE", True
            )
            all_results.append(ch_original_prewhere)
            time.sleep(1)

            # ClickHouse 최적화 (granularity=256, WHERE)
            ch_optimized_where = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login_optimized", "MergeTree", "Optimized-WHERE", False
            )
            all_results.append(ch_optimized_where)
            time.sleep(1)

            # ClickHouse 최적화 (granularity=256, PREWHERE)
            ch_optimized_prewhere = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login_optimized", "MergeTree", "Optimized-PREWHERE", True
            )
            all_results.append(ch_optimized_prewhere)
            time.sleep(1)

            # ClickHouse Memory 엔진 (WHERE)
            ch_memory_where = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login_memory", "Memory", "Memory-WHERE", False
            )
            all_results.append(ch_memory_where)
            time.sleep(1)

            # ClickHouse Memory 엔진 (PREWHERE)
            ch_memory_prewhere = self.run_benchmark(
                "ClickHouse", self.CLICKHOUSE_CONFIG, concurrency,
                "player_last_login_memory", "Memory", "Memory-PREWHERE", True
            )
            all_results.append(ch_memory_prewhere)
            time.sleep(2)

        return all_results

    def generate_report(self, results: List[BenchmarkResult]) -> str:
        report = []
        report.append("\n" + "="*100)
        report.append("MySQL vs ClickHouse Comprehensive Optimization Report")
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append("="*100)

        concurrency_levels = sorted(set(r.concurrency for r in results))

        report.append("\n## Summary by Concurrency")
        for conc in concurrency_levels:
            report.append(f"\n### Concurrency: {conc}")
            report.append("-" * 120)
            report.append(f"{'Target':<15} {'Engine':<12} {'Optimization':<20} {'QPS':>12} {'Avg(ms)':>10} {'P50(ms)':>10} {'P95(ms)':>10} {'P99(ms)':>10}")
            report.append("-" * 120)

            for r in [x for x in results if x.concurrency == conc]:
                report.append(f"{r.target:<15} {r.table_engine:<12} {r.optimization:<20} "
                            f"{r.qps:>12,.2f} {r.avg_latency_ms:>10.2f} {r.p50_latency_ms:>10.2f} "
                            f"{r.p95_latency_ms:>10.2f} {r.p99_latency_ms:>10.2f}")

        report.append("\n\n## Performance Comparison (vs MySQL)")
        for conc in concurrency_levels:
            mysql_r = next((r for r in results if r.concurrency == conc and r.target == "MySQL"), None)
            if not mysql_r:
                continue

            report.append(f"\n### Concurrency {conc} (MySQL QPS: {mysql_r.qps:,.2f})")
            report.append("-" * 80)

            ch_results = [r for r in results if r.concurrency == conc and r.target == "ClickHouse"]
            for ch_r in ch_results:
                ratio = ch_r.qps / mysql_r.qps if mysql_r.qps > 0 else 0
                improvement = ((ch_r.qps - mysql_r.qps) / mysql_r.qps * 100) if mysql_r.qps > 0 else 0
                report.append(f"{ch_r.optimization:<30} QPS: {ch_r.qps:>10,.2f}  Ratio: {ratio:>6.2f}x  Change: {improvement:>+7.1f}%")

        return "\n".join(report)


def main():
    print("MySQL vs ClickHouse Comprehensive Optimization Benchmark")
    print("=" * 60)
    print("Testing configurations:")
    print("  1. MySQL (InnoDB)")
    print("  2. ClickHouse Original (index_granularity=8192, WHERE)")
    print("  3. ClickHouse Original (index_granularity=8192, PREWHERE)")
    print("  4. ClickHouse Optimized (index_granularity=256, WHERE)")
    print("  5. ClickHouse Optimized (index_granularity=256, PREWHERE)")
    print("  6. ClickHouse Memory (WHERE)")
    print("  7. ClickHouse Memory (PREWHERE)")
    print("=" * 60)

    benchmark = ComprehensiveBenchmark()
    results = benchmark.run_all_benchmarks([8, 16, 24, 32])

    report = benchmark.generate_report(results)
    print(report)

    # 파일 저장
    with open("benchmark_comprehensive_report.txt", "w") as f:
        f.write(report)

    json_results = [
        {
            "target": r.target,
            "table_engine": r.table_engine,
            "optimization": r.optimization,
            "concurrency": r.concurrency,
            "qps": r.qps,
            "avg_latency_ms": r.avg_latency_ms,
            "p50_latency_ms": r.p50_latency_ms,
            "p95_latency_ms": r.p95_latency_ms,
            "p99_latency_ms": r.p99_latency_ms,
        }
        for r in results
    ]

    with open("benchmark_comprehensive_results.json", "w") as f:
        json.dump(json_results, f, indent=2)

    print("\nSaved: benchmark_comprehensive_report.txt, benchmark_comprehensive_results.json")


if __name__ == "__main__":
    main()
