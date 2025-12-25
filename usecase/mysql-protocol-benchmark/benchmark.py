#!/usr/bin/env python3
"""
MySQL vs ClickHouse Point Query Benchmark
- MySQL 네이티브 vs ClickHouse MySQL Protocol 성능 비교
- 동시성: 20, 40, 80, 100
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
    
    @property
    def min_latency_ms(self) -> float:
        return min(self.latencies_ms) if self.latencies_ms else 0
    
    @property
    def max_latency_ms(self) -> float:
        return max(self.latencies_ms) if self.latencies_ms else 0


class DatabaseBenchmark:
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
        # MySQL connector pool size max is 32
        pool_config["pool_size"] = min(pool_size, 32)
        pool_config["pool_name"] = f"pool_{config['port']}_{pool_size}"
        # ClickHouse MySQL protocol doesn't support reset_session
        pool_config["pool_reset_session"] = False
        return pooling.MySQLConnectionPool(**pool_config)
    
    def execute_single_query(self, pool, player_id: int) -> tuple:
        query = f"""
            SELECT player_id, player_name, character_id, character_name,
                   character_level, character_class, server_id, server_name,
                   last_login_at, currency_gold, currency_diamond
            FROM player_last_login 
            WHERE player_id = {player_id}
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
    
    def worker_thread(self, pool, player_ids: List[int], results_list: list, lock: threading.Lock):
        local_latencies = []
        local_success = 0
        local_fail = 0
        
        for pid in player_ids:
            success, latency, _ = self.execute_single_query(pool, pid)
            if success:
                local_latencies.append(latency)
                local_success += 1
            else:
                local_fail += 1
        
        with lock:
            results_list.extend(local_latencies)
            results_list.append(('stats', local_success, local_fail))
    
    def run_benchmark(self, target: str, config: dict, concurrency: int) -> BenchmarkResult:
        print(f"\n{'='*60}")
        print(f"Running: {target} | Concurrency: {concurrency}")
        print(f"{'='*60}")
        
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
            self.execute_single_query(pool, pid)
        
        print(f"Executing {total_queries} queries...")
        start_time = time.perf_counter()
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = [
                executor.submit(self.worker_thread, pool, chunk, results_list, lock)
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
            mysql_result = self.run_benchmark("MySQL", self.MYSQL_CONFIG, concurrency)
            all_results.append(mysql_result)
            
            ch_result = self.run_benchmark("ClickHouse", self.CLICKHOUSE_CONFIG, concurrency)
            all_results.append(ch_result)
            
            time.sleep(2)
        
        return all_results
    
    def generate_report(self, results: List[BenchmarkResult]) -> str:
        report = []
        report.append("\n" + "="*80)
        report.append("MySQL vs ClickHouse Point Query Performance Report")
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append("="*80)
        
        concurrency_levels = sorted(set(r.concurrency for r in results))
        
        report.append("\n## Summary")
        report.append("-" * 95)
        report.append(f"{'Concurrency':<12} {'Target':<12} {'QPS':>12} {'Avg(ms)':>10} {'P50(ms)':>10} {'P95(ms)':>10} {'P99(ms)':>10}")
        report.append("-" * 95)
        
        for conc in concurrency_levels:
            for r in [x for x in results if x.concurrency == conc]:
                report.append(f"{r.concurrency:<12} {r.target:<12} {r.qps:>12,.2f} {r.avg_latency_ms:>10.2f} {r.p50_latency_ms:>10.2f} {r.p95_latency_ms:>10.2f} {r.p99_latency_ms:>10.2f}")
            report.append("-" * 95)
        
        report.append("\n## Comparison (ClickHouse / MySQL)")
        for conc in concurrency_levels:
            mysql_r = next((r for r in results if r.concurrency == conc and r.target == "MySQL"), None)
            ch_r = next((r for r in results if r.concurrency == conc and r.target == "ClickHouse"), None)
            
            if mysql_r and ch_r:
                qps_ratio = ch_r.qps / mysql_r.qps if mysql_r.qps > 0 else 0
                report.append(f"Concurrency {conc}: QPS ratio = {qps_ratio:.2f}x")
        
        return "\n".join(report)


def main():
    print("MySQL vs ClickHouse Point Query Benchmark")
    print("=" * 50)

    benchmark = DatabaseBenchmark()
    results = benchmark.run_all_benchmarks([8, 16, 24, 32])
    
    report = benchmark.generate_report(results)
    print(report)
    
    with open("benchmark_report.txt", "w") as f:
        f.write(report)
    
    json_results = [
        {
            "target": r.target,
            "concurrency": r.concurrency,
            "qps": r.qps,
            "avg_latency_ms": r.avg_latency_ms,
            "p50_latency_ms": r.p50_latency_ms,
            "p95_latency_ms": r.p95_latency_ms,
            "p99_latency_ms": r.p99_latency_ms,
        }
        for r in results
    ]
    
    with open("benchmark_results.json", "w") as f:
        json.dump(json_results, f, indent=2)
    
    print("\nSaved: benchmark_report.txt, benchmark_results.json")


if __name__ == "__main__":
    main()
