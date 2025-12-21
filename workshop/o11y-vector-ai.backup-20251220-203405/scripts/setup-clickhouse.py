#!/usr/bin/env python3
"""
ClickHouse Schema Setup Script
Creates database and tables for O11y Vector AI project
"""
import os
import sys
from pathlib import Path

try:
    import clickhouse_connect
except ImportError:
    print("❌ clickhouse-connect 패키지가 설치되어 있지 않습니다.")
    print("\n설치 방법:")
    print("  pip install clickhouse-connect")
    sys.exit(1)

def load_env():
    """Load .env file"""
    env_file = Path(__file__).parent.parent / '.env'
    if not env_file.exists():
        print("❌ .env 파일을 찾을 수 없습니다.")
        print("\n먼저 다음을 실행하세요:")
        print("  ./quick-start.sh")
        sys.exit(1)

    env_vars = {}
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                env_vars[key] = value

    return env_vars

def connect_clickhouse(env):
    """Connect to ClickHouse"""
    try:
        client = clickhouse_connect.get_client(
            host=env['CLICKHOUSE_HOST'],
            port=int(env['CLICKHOUSE_PORT']),
            username=env['CLICKHOUSE_USER'],
            password=env['CLICKHOUSE_PASSWORD'],
            secure=True
        )
        # Test connection
        client.command('SELECT 1')
        return client
    except Exception as e:
        print(f"❌ ClickHouse 연결 실패: {e}")
        print("\n연결 정보를 확인하세요:")
        print(f"  Host: {env['CLICKHOUSE_HOST']}")
        print(f"  Port: {env['CLICKHOUSE_PORT']}")
        print(f"  User: {env['CLICKHOUSE_USER']}")
        sys.exit(1)

def execute_sql_file(client, sql_file, db_name):
    """Execute SQL file statement by statement"""
    if not sql_file.exists():
        print(f"❌ SQL 파일을 찾을 수 없습니다: {sql_file}")
        return False

    print(f"\n처리 중: {sql_file.name}")

    with open(sql_file) as f:
        content = f.read()

    # Remove comments
    lines = []
    for line in content.split('\n'):
        # Remove inline comments
        if '--' in line:
            line = line.split('--')[0]
        line = line.strip()
        if line:
            lines.append(line)

    # Join lines and split by semicolon
    full_sql = ' '.join(lines)
    statements = [s.strip() for s in full_sql.split(';') if s.strip()]

    print(f"  총 {len(statements)}개 구문 실행...")

    for i, statement in enumerate(statements, 1):
        try:
            client.command(statement)
            # Print progress for large files
            if i % 5 == 0 or i == len(statements):
                print(f"  진행: {i}/{len(statements)}")
        except Exception as e:
            error_msg = str(e)
            # Ignore "already exists" errors
            if 'already exists' in error_msg.lower() or 'code: 57' in error_msg:
                print(f"  ⚠️  구문 {i}: 이미 존재함 (무시)")
                continue
            # Print other errors but continue
            print(f"  ⚠️  구문 {i} 경고: {error_msg[:200]}")

    print(f"  ✅ 완료")
    return True

def main():
    print("=" * 70)
    print("ClickHouse Schema Setup (Python)")
    print("=" * 70)

    # Load environment variables
    print("\n📂 환경 변수 로딩 중...")
    env = load_env()
    print(f"  ✅ ClickHouse Host: {env['CLICKHOUSE_HOST']}")
    print(f"  ✅ Database: {env['CLICKHOUSE_DB']}")

    # Connect to ClickHouse
    print("\n🔌 ClickHouse 연결 중...")
    client = connect_clickhouse(env)
    print("  ✅ 연결 성공")

    # Create database
    db_name = env['CLICKHOUSE_DB']
    print(f"\n🗄️  데이터베이스 '{db_name}' 생성 중...")
    try:
        client.command(f'CREATE DATABASE IF NOT EXISTS {db_name}')
        print(f"  ✅ 데이터베이스 준비 완료")
    except Exception as e:
        print(f"  ❌ 데이터베이스 생성 실패: {e}")
        sys.exit(1)

    # Get SQL files
    base_dir = Path(__file__).parent.parent
    schemas_dir = base_dir / 'clickhouse' / 'schemas'

    sql_files = [
        schemas_dir / '01_otel_tables.sql',
        schemas_dir / '02_vector_tables.sql',
    ]

    # Execute SQL files
    print(f"\n📊 스키마 생성 중...")
    all_success = True
    for sql_file in sql_files:
        if not execute_sql_file(client, sql_file, db_name):
            all_success = False

    # Verify tables
    print("\n" + "=" * 70)
    print("🔍 생성된 테이블 확인")
    print("=" * 70)

    try:
        result = client.query(f"SHOW TABLES FROM {db_name}")
        tables = sorted([row[0] for row in result.result_rows])

        expected_tables = [
            'error_patterns',
            'logs_with_embeddings',
            'otel_logs',
            'otel_sessions',
            'otel_traces',
            'session_replay_events',
            'traces_with_embeddings',
        ]

        print(f"\n생성된 테이블 ({len(tables)}개):")
        for table in tables:
            status = "✅" if table in expected_tables else "ℹ️"
            print(f"  {status} {table}")

        missing = set(expected_tables) - set(tables)
        if missing:
            print(f"\n⚠️  누락된 테이블 ({len(missing)}개):")
            for table in sorted(missing):
                print(f"  ❌ {table}")
            all_success = False

    except Exception as e:
        print(f"❌ 테이블 확인 실패: {e}")
        all_success = False

    # Final message
    print("\n" + "=" * 70)
    if all_success and len(tables) >= len(expected_tables):
        print("✅ 스키마 설정 완료!")
        print("=" * 70)
        print("\n다음 단계:")
        print("  docker-compose up -d")
        return 0
    else:
        print("⚠️  스키마 설정이 완전히 완료되지 않았습니다.")
        print("=" * 70)
        print("\n위의 경고 메시지를 확인하고 다시 실행하거나,")
        print("ClickHouse 콘솔에서 직접 확인해보세요.")
        return 1

if __name__ == '__main__':
    sys.exit(main())
