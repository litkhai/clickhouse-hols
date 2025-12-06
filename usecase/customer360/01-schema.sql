-- ============================================================================
-- Customer 360 Lab Step 1: Database and Table Creation
-- Customer 360 실습 Step 1: 데이터베이스 및 테이블 생성
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Create database and tables for Customer 360 analytics
-- 목적: Customer 360 분석을 위한 데이터베이스 및 테이블 생성
-- ============================================================================

-- Create database (skip if exists)
-- 데이터베이스 생성 (이미 존재하면 무시)
CREATE DATABASE IF NOT EXISTS customer360;

-- ============================================================================
-- 1.1 Customer Profile Table
-- 1.1 고객 프로필 테이블
-- ============================================================================
-- Features: Central customer information, demographic data
-- 특징: 중앙 고객 정보, 인구통계 데이터
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.customers (
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    email String,                          -- Email address / 이메일 주소
    phone String,                          -- Phone number / 전화번호
    first_name String,                     -- First name / 이름
    last_name String,                      -- Last name / 성
    date_of_birth Date,                    -- Date of birth / 생년월일
    gender Enum8('M' = 1, 'F' = 2, 'O' = 3),  -- Gender / 성별
    country String,                        -- Country / 국가
    city String,                           -- City / 도시
    postal_code String,                    -- Postal code / 우편번호
    registration_date DateTime,            -- Registration date / 가입일
    customer_segment Enum8('VIP' = 1, 'Premium' = 2, 'Standard' = 3, 'New' = 4),  -- Customer segment / 고객 세그먼트
    lifetime_value Decimal(12, 2),         -- Lifetime value / 생애 가치
    credit_score UInt16,                   -- Credit score / 신용점수
    is_active Bool,                        -- Active status / 활성 상태
    last_updated DateTime DEFAULT now()    -- Last update timestamp / 최종 업데이트 시간
) ENGINE = MergeTree()
ORDER BY (customer_id)                     -- Primary sorting key / 기본 정렬 키
PRIMARY KEY customer_id
SETTINGS index_granularity = 8192;

-- ============================================================================
-- 1.2 Transaction History Table (with partitioning)
-- 1.2 거래 이력 테이블 (파티션 적용)
-- ============================================================================
-- Features: Purchase history, monthly partitioning for efficient queries
-- 특징: 구매 이력, 효율적인 쿼리를 위한 월별 파티셔닝
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.transactions (
    transaction_id UInt64,                 -- Transaction identifier / 거래 식별자
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    transaction_date DateTime,             -- Transaction date / 거래 날짜
    transaction_type Enum8('purchase' = 1, 'refund' = 2, 'exchange' = 3),  -- Transaction type / 거래 유형
    product_id UInt32,                     -- Product identifier / 제품 식별자
    product_category LowCardinality(String),  -- Product category / 제품 카테고리
    product_name String,                   -- Product name / 제품명
    quantity UInt16,                       -- Quantity / 수량
    unit_price Decimal(10, 2),             -- Unit price / 단가
    total_amount Decimal(12, 2),           -- Total amount / 총액
    discount_amount Decimal(10, 2),        -- Discount amount / 할인액
    payment_method LowCardinality(String), -- Payment method / 결제 수단
    channel Enum8('online' = 1, 'mobile_app' = 2, 'store' = 3, 'phone' = 4),  -- Sales channel / 판매 채널
    store_id UInt32,                       -- Store identifier / 매장 식별자
    is_first_purchase Bool                 -- First purchase flag / 첫 구매 여부
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(transaction_date)    -- Monthly partitioning / 월별 파티셔닝
ORDER BY (customer_id, transaction_date, transaction_id)  -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;

-- ============================================================================
-- 1.3 Customer Interaction Events (Web/App Activity)
-- 1.3 고객 인터랙션 이벤트 (웹/앱 활동)
-- ============================================================================
-- Features: Customer behavior tracking, session analysis
-- 특징: 고객 행동 추적, 세션 분석
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.customer_events (
    event_id UInt64,                       -- Event identifier / 이벤트 식별자
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    event_timestamp DateTime64(3),         -- Event timestamp (millisecond precision) / 이벤트 타임스탬프 (밀리초 정밀도)
    event_type LowCardinality(String),     -- Event type / 이벤트 타입
    page_url String,                       -- Page URL / 페이지 URL
    session_id String,                     -- Session identifier / 세션 식별자
    device_type Enum8('desktop' = 1, 'mobile' = 2, 'tablet' = 3),  -- Device type / 기기 유형
    browser LowCardinality(String),        -- Browser / 브라우저
    referrer_source LowCardinality(String),  -- Referrer source / 유입 경로
    duration_seconds UInt32,               -- Duration in seconds / 체류 시간 (초)
    event_properties String                -- JSON format / JSON 형태
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_timestamp)     -- Monthly partitioning / 월별 파티셔닝
ORDER BY (customer_id, event_timestamp)    -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;

-- ============================================================================
-- 1.4 Customer Service Tickets
-- 1.4 고객 서비스 티켓
-- ============================================================================
-- Features: Support ticket tracking, satisfaction measurement
-- 특징: 지원 티켓 추적, 만족도 측정
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.support_tickets (
    ticket_id UInt64,                      -- Ticket identifier / 티켓 식별자
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    created_at DateTime,                   -- Creation timestamp / 생성 시간
    resolved_at Nullable(DateTime),        -- Resolution timestamp / 해결 시간
    category LowCardinality(String),       -- Ticket category / 티켓 카테고리
    priority Enum8('low' = 1, 'medium' = 2, 'high' = 3, 'urgent' = 4),  -- Priority level / 우선순위
    status Enum8('open' = 1, 'in_progress' = 2, 'resolved' = 3, 'closed' = 4),  -- Ticket status / 티켓 상태
    channel Enum8('email' = 1, 'phone' = 2, 'chat' = 3, 'social' = 4),  -- Contact channel / 연락 채널
    agent_id UInt32,                       -- Agent identifier / 상담원 식별자
    satisfaction_score Nullable(UInt8),    -- Customer satisfaction score / 고객 만족도 점수
    resolution_time_hours Nullable(Float32)  -- Resolution time in hours / 해결 시간 (시간)
) ENGINE = MergeTree()
ORDER BY (customer_id, created_at)         -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;

-- ============================================================================
-- 1.5 Marketing Campaign Responses
-- 1.5 마케팅 캠페인 응답
-- ============================================================================
-- Features: Campaign effectiveness tracking, conversion analysis
-- 특징: 캠페인 효과 추적, 전환 분석
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.campaign_responses (
    response_id UInt64,                    -- Response identifier / 응답 식별자
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    campaign_id UInt32,                    -- Campaign identifier / 캠페인 식별자
    campaign_name String,                  -- Campaign name / 캠페인명
    campaign_type Enum8('email' = 1, 'sms' = 2, 'push' = 3, 'social' = 4, 'display' = 5),  -- Campaign type / 캠페인 유형
    sent_at DateTime,                      -- Send timestamp / 발송 시간
    opened_at Nullable(DateTime),          -- Open timestamp / 오픈 시간
    clicked_at Nullable(DateTime),         -- Click timestamp / 클릭 시간
    converted_at Nullable(DateTime),       -- Conversion timestamp / 전환 시간
    conversion_value Nullable(Decimal(10, 2))  -- Conversion value / 전환 가치
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(sent_at)             -- Monthly partitioning / 월별 파티셔닝
ORDER BY (customer_id, sent_at)            -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;

-- ============================================================================
-- 1.6 Product Reviews
-- 1.6 제품 리뷰
-- ============================================================================
-- Features: Product feedback, rating analysis
-- 특징: 제품 피드백, 평점 분석
-- ============================================================================

CREATE TABLE IF NOT EXISTS customer360.product_reviews (
    review_id UInt64,                      -- Review identifier / 리뷰 식별자
    customer_id UInt64,                    -- Customer identifier / 고객 식별자
    product_id UInt32,                     -- Product identifier / 제품 식별자
    rating UInt8,                          -- Rating (1-5) / 평점 (1-5)
    review_text String,                    -- Review text / 리뷰 내용
    review_date DateTime,                  -- Review date / 리뷰 날짜
    helpful_count UInt32,                  -- Helpful count / 도움됨 수
    verified_purchase Bool                 -- Verified purchase flag / 검증된 구매 여부
) ENGINE = MergeTree()
ORDER BY (customer_id, review_date)        -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Verify Schema Creation
-- 스키마 생성 확인
-- ============================================================================

SELECT
    name AS table_name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'customer360'
ORDER BY name;
