#!/bin/bash
# MySQL 클라이언트 설치 및 확인 스크립트

echo "MySQL 클라이언트 확인 중..."
echo ""

# OS 확인
OS_TYPE=$(uname -s)
echo "운영체제: ${OS_TYPE}"
echo ""

# MySQL 클라이언트 확인
MYSQL_INSTALLED=false

if command -v mysql &> /dev/null; then
    MYSQL_VERSION=$(mysql --version)
    echo "✓ MySQL 클라이언트가 이미 설치되어 있습니다:"
    echo "  ${MYSQL_VERSION}"
    MYSQL_INSTALLED=true
else
    echo "MySQL 클라이언트가 설치되어 있지 않습니다."
fi

echo ""

# OS별 설치 가이드
if [ "${MYSQL_INSTALLED}" = false ]; then
    case "${OS_TYPE}" in
        Darwin*)
            echo "macOS에서 MySQL 클라이언트 설치 확인..."
            if command -v brew &> /dev/null; then
                echo "✓ Homebrew가 설치되어 있습니다."
                # 자동으로 설치 진행
                if brew list mysql-client &> /dev/null 2>&1; then
                    echo "✓ MySQL 클라이언트가 Homebrew에 설치되어 있습니다."
                    export PATH="/opt/homebrew/opt/mysql-client/bin:/usr/local/opt/mysql-client/bin:$PATH"
                else
                    echo "MySQL 클라이언트 설치 중... (자동 설치)"
                    brew install mysql-client
                    export PATH="/opt/homebrew/opt/mysql-client/bin:/usr/local/opt/mysql-client/bin:$PATH"
                    echo "✓ MySQL 클라이언트 설치 완료"
                fi
                MYSQL_INSTALLED=true
            else
                echo "WARNING: Homebrew가 설치되어 있지 않습니다."
                echo "MySQL 클라이언트 없이 계속합니다. Python 드라이버로만 테스트합니다."
            fi
            ;;
        Linux*)
            echo "Linux에서 MySQL 클라이언트 설치 방법:"
            echo ""
            echo "Ubuntu/Debian:"
            echo "  sudo apt-get update && sudo apt-get install mysql-client"
            echo ""
            echo "CentOS/RHEL:"
            echo "  sudo yum install mysql"
            echo ""
            echo "WARNING: 수동 설치 필요. Python 드라이버로만 테스트합니다."
            ;;
        *)
            echo "지원하지 않는 운영체제: ${OS_TYPE}"
            echo "WARNING: Python 드라이버로만 테스트합니다."
            ;;
    esac
fi

# MySQL 버전 확인
if command -v mysql &> /dev/null; then
    MYSQL_VERSION=$(mysql --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    MYSQL_MAJOR=$(echo "${MYSQL_VERSION}" | cut -d. -f1)

    echo ""
    echo "설치된 MySQL 클라이언트 버전: ${MYSQL_VERSION}"
    echo "Major 버전: ${MYSQL_MAJOR}"

    if [ "${MYSQL_MAJOR}" -ge 5 ]; then
        echo "✓ MySQL 클라이언트 버전 확인 완료 (버전 5 이상)"
    else
        echo "WARNING: MySQL 5 이상 권장"
    fi
else
    echo ""
    echo "WARNING: MySQL 클라이언트가 설치되지 않았습니다."
    echo "Python 드라이버로만 테스트를 진행합니다."
fi

echo ""
echo "✓ MySQL 클라이언트 확인 완료"
exit 0
