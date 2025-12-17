#!/usr/bin/env python3
"""
ClickHouse Deduplication Test Suite - 전체 테스트 실행
"""

import sys
from config import TestConfig
from utils import ClickHouseClient, print_header
import phase1_engine_comparison
import phase2_insert_patterns
import phase3_architecture

def print_menu():
    """메뉴 출력"""
    print("\n" + "=" * 70)
    print("  ClickHouse Deduplication Test Suite")
    print("=" * 70)
    print("\n실행할 테스트를 선택하세요:")
    print("  1. Phase 1: Engine 비교 테스트")
    print("  2. Phase 2: Insert 패턴별 성능 테스트")
    print("  3. Phase 3: 권장 아키텍처 검증")
    print("  4. 전체 테스트 실행")
    print("  0. 종료")
    print()

def run_test_suite():
    """전체 테스트 실행"""
    print_header("전체 테스트 실행")

    # 연결 테스트
    config = TestConfig()
    try:
        client = ClickHouseClient(config)
        print()
    except Exception as e:
        print(f"\n✗ ClickHouse 연결 실패. 프로그램을 종료합니다.")
        return False

    # Phase 1
    print("\n\n" + "=" * 70)
    print("  Phase 1/3 시작")
    print("=" * 70)
    try:
        phase1_engine_comparison.run_phase1()
    except Exception as e:
        print(f"\n✗ Phase 1 실패: {e}")
        return False

    # Phase 2
    print("\n\n" + "=" * 70)
    print("  Phase 2/3 시작")
    print("=" * 70)
    try:
        phase2_insert_patterns.run_phase2()
    except Exception as e:
        print(f"\n✗ Phase 2 실패: {e}")
        return False

    # Phase 3
    print("\n\n" + "=" * 70)
    print("  Phase 3/3 시작")
    print("=" * 70)
    try:
        phase3_architecture.run_phase3()
    except Exception as e:
        print(f"\n✗ Phase 3 실패: {e}")
        return False

    print("\n\n" + "=" * 70)
    print("  ✓ 전체 테스트 완료")
    print("=" * 70)
    return True

def main():
    """메인 함수"""
    if len(sys.argv) > 1:
        # CLI 모드
        phase = sys.argv[1]
        if phase == "1":
            phase1_engine_comparison.run_phase1()
        elif phase == "2":
            phase2_insert_patterns.run_phase2()
        elif phase == "3":
            phase3_architecture.run_phase3()
        elif phase == "all":
            run_test_suite()
        else:
            print(f"알 수 없는 옵션: {phase}")
            print("사용법: python3 run_all_tests.py [1|2|3|all]")
    else:
        # 대화형 모드
        while True:
            print_menu()
            try:
                choice = input("선택 (0-4): ").strip()

                if choice == "0":
                    print("\n프로그램을 종료합니다.")
                    break
                elif choice == "1":
                    phase1_engine_comparison.run_phase1()
                elif choice == "2":
                    phase2_insert_patterns.run_phase2()
                elif choice == "3":
                    phase3_architecture.run_phase3()
                elif choice == "4":
                    run_test_suite()
                else:
                    print("\n잘못된 선택입니다. 0-4 사이의 숫자를 입력하세요.")

                input("\n\nEnter를 눌러 계속...")
            except KeyboardInterrupt:
                print("\n\n프로그램을 종료합니다.")
                break
            except Exception as e:
                print(f"\n에러 발생: {e}")
                import traceback
                traceback.print_exc()

if __name__ == '__main__':
    main()
