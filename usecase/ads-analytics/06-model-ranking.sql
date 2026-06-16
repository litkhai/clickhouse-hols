-- ============================================================================
-- ads-analytics Step 6: ML Ranking Quality — Distributions, Gaps, Capping
-- ads-analytics 6단계: ML 랭킹 품질 — 분포, 갭, 캡핑
-- ============================================================================
-- The same wide row carries model signals (rawPCtr, qualityScore, cappedScore).
-- This step mixes exact conditional aggregates with quantile/distribution
-- functions to measure model calibration and the auction's capping behavior.
-- 동일 와이드 row에 모델 신호(rawPCtr, qualityScore, cappedScore)가 함께 들어 있음.
-- 이 단계는 조건부 집계와 quantile/분포 함수를 섞어 모델 보정 정도와 경매의
-- 캡핑 동작을 측정.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 6.1 Score distributions — avg, median, tail quantiles
-- 6.1 점수 분포 — 평균, 중앙값, 꼬리 분위수
-- ---------------------------------------------------------------------------
-- quantile() is approximate (reservoir); quantileExact() is exact but heavier.
-- quantile()은 근사(reservoir), quantileExact()은 정확하지만 더 무거움.

SELECT
    round(avg(rawPCtr), 5)                                             AS avg_raw_pctr,
    round(avg(cappedScore), 5)                                        AS avg_capped_pctr,
    round(avg(rawPctcvr), 5)                                          AS avg_raw_pctcvr,
    round(quantile(0.50)(rawPCtr), 5)                                 AS median_raw_pctr,
    round(quantile(0.95)(rawPCtr), 5)                                 AS p95_raw_pctr,
    round(quantile(0.99)(rawPCtr), 5)                                 AS p99_raw_pctr
FROM ad_analytics.ad_events;

-- ---------------------------------------------------------------------------
-- 6.2 Calibration gap — predicted pCTR vs measured CTR
-- 6.2 보정 갭 — 예측 pCTR vs 실측 CTR
-- ---------------------------------------------------------------------------
-- A well-calibrated model has avg(pCTR) ≈ actual CTR. The gap (in pp) surfaces
-- over/under-prediction per channel.
-- 잘 보정된 모델은 avg(pCTR) ≈ 실제 CTR. 갭(pp)은 채널별 과/저 예측을 드러냄.

SELECT
    channelType,
    round(avg(rawPCtr) * 100, 4)                                      AS pred_ctr_pct,
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 4)          AS actual_ctr_pct,
    round(avg(rawPCtr) * 100
          - countIf(eventType = 'CLICK') * 100.0
            / nullIf(countIf(eventType = 'IMPRESSION'), 0), 4)        AS gap_pp
FROM   ad_analytics.ad_events
GROUP  BY channelType
ORDER  BY channelType;

-- ---------------------------------------------------------------------------
-- 6.3 Capping behavior — how often quality score is adjusted
-- 6.3 캡핑 동작 — 품질 점수가 조정되는 빈도
-- ---------------------------------------------------------------------------
-- Lower/Higher capped use the source-doc definitions (raw vs capped direction);
-- Capping Ratio = any adjustment.
-- Lower/Higher capped는 원본 문서 정의(raw vs capped 방향)를 따름;
-- Capping Ratio = 조정이 일어난 전체 비율.

SELECT
    candidateSource,
    round(countIf(rawQualityScore < qualityScore) * 100.0
          / nullIf(count(), 0), 2)                                    AS lower_capped_pct,
    round(countIf(rawQualityScore > qualityScore) * 100.0
          / nullIf(count(), 0), 2)                                    AS higher_capped_pct,
    round(countIf(rawQualityScore != qualityScore) * 100.0
          / nullIf(count(), 0), 2)                                    AS capping_pct
FROM   ad_analytics.ad_events
GROUP  BY candidateSource
ORDER  BY candidateSource;

-- ---------------------------------------------------------------------------
-- 6.4 Rank movement — candidate rank vs final served rank
-- 6.4 랭크 이동 — 후보 랭크 vs 최종 노출 랭크
-- ---------------------------------------------------------------------------

SELECT
    candidateSource,
    round(avg(rank), 3)                                               AS avg_rank,
    round(avg(candidateRank), 3)                                      AS avg_candidate_rank,
    round(avg(candidateRank) - avg(rank), 3)                          AS avg_movement,
    round(avg(responseCount), 2)                                      AS avg_response_count
FROM   ad_analytics.ad_events
GROUP  BY candidateSource
ORDER  BY avg_movement DESC;

-- ---------------------------------------------------------------------------
-- 6.5 eCPM-style ranking score & bid efficiency
-- 6.5 eCPM 스타일 랭킹 점수 & 입찰 효율
-- ---------------------------------------------------------------------------
-- Ranking Score ≈ quality * bid (eCPM proxy). Avg bid param = bid per unit
-- quality (price efficiency).
-- Ranking Score ≈ 품질 × 입찰가 (eCPM 추정). Avg bid param = 품질 단위당 입찰가.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    campaignGoal,
    round(avg(qualityScore), 4)                                       AS avg_quality,
    round(avg(bidPrice) / SCALE, 4)                                   AS avg_bid,
    round(avg(qualityScore) * avg(bidPrice) / SCALE, 4)               AS ranking_score,
    round(avg(bidPrice / nullIf(qualityScore, 0)) / SCALE, 4)         AS bid_per_quality
FROM   ad_analytics.ad_events
GROUP  BY campaignGoal
ORDER  BY ranking_score DESC;

SELECT 'Step 6 complete — model calibration & auction capping, all in one pass.' AS done;
