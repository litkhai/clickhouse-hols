FROM python:3.12-slim

WORKDIR /app

# 의존성 먼저 (레이어 캐시)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 코드 복사 (.dockerignore 로 .env 등 시크릿은 제외됨)
COPY scripts/ ./scripts/
COPY sql/ ./sql/
COPY webapp/ ./webapp/

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/scripts \
    PORT=8080

EXPOSE 8080
CMD ["python", "webapp/app.py"]
