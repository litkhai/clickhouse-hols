-- ================================================
-- 벤치마크 쿼리
-- Benchmark Queries
-- ================================================

-- ================================================
-- Q1: Range Query (위치 기반 검색)
-- Q1: Range Query (Position-based Search)
-- BRCA1 유전자 영역 조회 (chr17:7,577,000-7,578,000)
-- Query BRCA1 gene region (chr17:7,577,000-7,578,000)
-- ================================================
SELECT
    chromosome,
    position,
    gene,
    ref,
    alt,
    impact,
    consequence,
    cadd_phred,
    clinvar_significance
FROM genome.variants_full
WHERE chromosome = 'chr17'
  AND position BETWEEN 7577000 AND 7578000
ORDER BY position
LIMIT 1000;

-- EXPLAIN 실행 계획 확인
-- Check EXPLAIN execution plan
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE chromosome = 'chr17'
  AND position BETWEEN 7577000 AND 7578000;

-- ================================================
-- Q2: Gene Filtering (유전자 필터링)
-- Q2: Gene Filtering
-- BRCA1 유전자의 HIGH impact 변이
-- HIGH impact variants in BRCA1 gene
-- ================================================
SELECT
    gene,
    chromosome,
    position,
    consequence,
    impact,
    hgvs_p,
    cadd_phred,
    sift_pred,
    polyphen2_pred
FROM genome.variants_full
WHERE gene = 'BRCA1'
  AND impact = 'HIGH'
ORDER BY cadd_phred DESC
LIMIT 100;

-- EXPLAIN으로 인덱스 사용 확인
-- Check index usage with EXPLAIN
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE gene = 'BRCA1'
  AND impact = 'HIGH';

-- ================================================
-- Q3: N-gram Search (부분 문자열 검색)
-- Q3: N-gram Search (Partial String Search)
-- BRCA로 시작하는 유전자 검색
-- Search for genes starting with BRCA
-- ================================================
SELECT
    gene,
    count(*) AS variant_count,
    countIf(impact = 'HIGH') AS high_impact_count,
    avg(cadd_phred) AS avg_cadd_phred
FROM genome.variants_full
WHERE gene LIKE 'BRCA%'
GROUP BY gene
ORDER BY variant_count DESC;

-- EXPLAIN으로 N-gram 인덱스 사용 확인
-- Check N-gram index usage with EXPLAIN
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE gene LIKE 'BRCA%';

-- ================================================
-- Q4: Aggregation (유전자별 통계)
-- Q4: Aggregation (Gene-level Statistics)
-- 유전자별 변이 개수 및 평균 CADD 점수
-- Variant counts and average CADD score per gene
-- ================================================
SELECT
    gene,
    count(*) AS total_variants,
    countIf(impact = 'HIGH') AS high_impact,
    countIf(impact = 'MODERATE') AS moderate_impact,
    countIf(clinvar_significance = 'Pathogenic') AS pathogenic_count,
    avg(cadd_phred) AS avg_cadd,
    max(cadd_phred) AS max_cadd
FROM genome.variants_full
GROUP BY gene
ORDER BY total_variants DESC
LIMIT 100;

-- ================================================
-- Q5: Complex Query (복합 조건)
-- Q5: Complex Query (Multiple Conditions)
-- HIGH impact + pathogenic + 희귀 변이 (AF < 0.01)
-- HIGH impact + pathogenic + rare variants (AF < 0.01)
-- ================================================
SELECT
    chromosome,
    position,
    gene,
    consequence,
    hgvs_p,
    cadd_phred,
    af_gnomad_all,
    clinvar_disease
FROM genome.variants_full
WHERE impact = 'HIGH'
  AND clinvar_significance = 'Pathogenic'
  AND af_gnomad_all < 0.01
ORDER BY cadd_phred DESC
LIMIT 100;

-- ================================================
-- Q6: Sample-specific Variant Lookup
-- Q6: 샘플별 변이 검색
-- 유즈케이스: 환자별 병원성 변이 리포트 생성
-- Use case: Generate pathogenic variant report per patient
-- ================================================
SELECT
    sample_id,
    chromosome,
    position,
    gene,
    consequence,
    zygosity,
    read_depth,
    clinvar_significance,
    clinvar_disease
FROM genome.variants_full
WHERE sample_id = 'SAMPLE_000001'
  AND clinvar_significance IN ('Pathogenic', 'Likely_pathogenic')
ORDER BY chromosome, position;

-- EXPLAIN 실행 계획
-- Check EXPLAIN execution plan
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE sample_id = 'SAMPLE_000001'
  AND clinvar_significance IN ('Pathogenic', 'Likely_pathogenic');

-- ================================================
-- Q7: Chromosome-wide Statistics
-- Q7: 염색체별 통계
-- 유즈케이스: 염색체별 변이 분포 분석 (품질 관리)
-- Use case: Chromosome-wide variant distribution analysis (QC)
-- ================================================
SELECT
    chromosome,
    count(*) AS total_variants,
    countIf(variant_type = 'SNP') AS snp_count,
    countIf(variant_type = 'InDel') AS indel_count,
    countIf(impact = 'HIGH') AS high_impact_count,
    avg(quality) AS avg_quality
FROM genome.variants_full
GROUP BY chromosome
ORDER BY
    CASE
        WHEN chromosome = 'chrX' THEN 23
        WHEN chromosome = 'chrY' THEN 24
        ELSE toUInt8(substring(chromosome, 4))
    END;

-- ================================================
-- Q8: Clinical Variant Hotspot Analysis
-- Q8: 임상 변이 핫스팟 분석
-- 유즈케이스: 질병 연관 유전자 핫스팟 식별
-- Use case: Identify disease-associated gene hotspots
-- ================================================
SELECT
    gene,
    count(*) AS pathogenic_count,
    countDistinct(clinvar_disease) AS disease_count,
    arrayStringConcat(groupUniqArray(5)(clinvar_disease), ', ') AS top_diseases,
    max(cadd_phred) AS max_cadd
FROM genome.variants_full
WHERE clinvar_significance = 'Pathogenic'
  AND impact = 'HIGH'
GROUP BY gene
HAVING pathogenic_count >= 10
ORDER BY pathogenic_count DESC
LIMIT 50;

-- EXPLAIN 실행 계획
-- Check EXPLAIN execution plan
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE clinvar_significance = 'Pathogenic'
  AND impact = 'HIGH';

-- ================================================
-- Q9: Population Frequency Distribution
-- Q9: 집단 빈도 분포
-- 유즈케이스: 집단별 allele frequency 비교 (인구유전학)
-- Use case: Compare allele frequency across populations (population genetics)
-- ================================================
SELECT
    CASE
        WHEN af_gnomad_eas < 0.001 THEN 'ultra_rare'
        WHEN af_gnomad_eas < 0.01 THEN 'rare'
        WHEN af_gnomad_eas < 0.05 THEN 'low_frequency'
        ELSE 'common'
    END AS frequency_class,
    count(*) AS variant_count,
    avg(af_gnomad_eas) AS avg_af_eas,
    avg(af_korean) AS avg_af_korean
FROM genome.variants_full
WHERE gene IN ('BRCA1', 'BRCA2', 'TP53')
GROUP BY frequency_class
ORDER BY variant_count DESC;

-- ================================================
-- Q10: Co-occurrence Analysis
-- Q10: 공존 패턴 분석
-- 유즈케이스: 동일 샘플 내 변이 공존 패턴 분석
-- Use case: Analyze variant co-occurrence patterns within samples
-- ================================================
SELECT
    sample_id,
    groupArray(gene) AS genes,
    count(*) AS variant_count,
    countIf(impact = 'HIGH') AS high_impact_count
FROM genome.variants_full
WHERE impact IN ('HIGH', 'MODERATE')
  AND chromosome IN ('chr17', 'chr13')
GROUP BY sample_id
HAVING variant_count >= 5
ORDER BY high_impact_count DESC
LIMIT 100;

-- EXPLAIN 실행 계획
-- Check EXPLAIN execution plan
EXPLAIN indexes = 1
SELECT count(*)
FROM genome.variants_full
WHERE impact IN ('HIGH', 'MODERATE')
  AND chromosome IN ('chr17', 'chr13');

-- ================================================
-- 3. Materialized View 활용 쿼리
-- 3. Materialized View Queries
-- ================================================

-- MV에서 유전자별 통계 조회 (사전 계산됨)
-- Query gene-level statistics from MV (pre-computed)
SELECT
    gene,
    countMerge(total_variants) AS total,
    countMerge(high_impact_count) AS high_impact,
    countMerge(pathogenic_count) AS pathogenic,
    avgMerge(avg_cadd_phred) AS avg_cadd,
    maxMerge(max_cadd_phred) AS max_cadd
FROM genome.gene_summary
GROUP BY gene
ORDER BY total DESC
LIMIT 100;

-- ================================================
-- 4. 성능 비교 쿼리
-- 4. Performance Comparison Queries
-- ================================================

-- Before: 원본 테이블에서 집계 (느림)
-- Before: Aggregate from original table (slow)
SELECT
    gene,
    count(*) AS total_variants,
    avgIf(cadd_phred, cadd_phred > 0) AS avg_cadd
FROM genome.variants_full
WHERE gene IN ('BRCA1', 'BRCA2', 'TP53', 'EGFR', 'KRAS')
GROUP BY gene;

-- After: Materialized View 사용 (빠름)
-- After: Use Materialized View (fast)
SELECT
    gene,
    countMerge(total_variants) AS total_variants,
    avgMerge(avg_cadd_phred) AS avg_cadd
FROM genome.gene_summary
WHERE gene IN ('BRCA1', 'BRCA2', 'TP53', 'EGFR', 'KRAS')
GROUP BY gene;
