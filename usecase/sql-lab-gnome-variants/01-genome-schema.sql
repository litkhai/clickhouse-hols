-- ================================================
-- 유전체 변이 데이터 스키마 (106 컬럼)
-- Genome Variant Data Schema (106 columns)
-- ClickHouse Cloud Production 환경
-- ClickHouse Cloud Production Environment
-- ================================================

CREATE DATABASE IF NOT EXISTS genome;

-- ================================================
-- Main Table: variants_full
-- ================================================
CREATE TABLE genome.variants_full (
    -- 1. 위치 및 기본 변이 정보 (8개)
    -- 1. Position and Basic Variant Information (8 fields)
    chromosome LowCardinality(String),
    position UInt32,
    ref String,
    alt String,
    variant_id String,                    -- rs ID (dbSNP)
    variant_type LowCardinality(String),  -- SNP, InDel
    quality Float32,
    filter LowCardinality(String),        -- PASS, LowQual

    -- 2. 유전자 및 전사체 정보 (6개)
    -- 2. Gene and Transcript Information (6 fields)
    gene LowCardinality(String),
    gene_id String,                       -- ENSG ID
    transcript_id String,                 -- ENST ID
    transcript_biotype LowCardinality(String),
    exon_number UInt8,
    intron_number UInt8,

    -- 3. 기능적 영향 (7개)
    -- 3. Functional Impact (7 fields)
    impact LowCardinality(String),        -- HIGH/MODERATE/LOW/MODIFIER
    consequence LowCardinality(String),   -- missense_variant, etc.
    hgvs_c String,                        -- DNA 변이 표기 / DNA variant notation
    hgvs_p String,                        -- 단백질 변이 표기 / Protein variant notation
    codon_change String,
    amino_acid_change String,
    protein_position UInt32,

    -- 4. 샘플 정보 (4개)
    -- 4. Sample Information (4 fields)
    sample_id String,
    sample_type LowCardinality(String),   -- germline, tumor, normal
    tissue_type LowCardinality(String),
    collection_date Date,

    -- 5. Genotype 정보 (7개)
    -- 5. Genotype Information (7 fields)
    genotype LowCardinality(String),      -- 0/1, 1/1
    zygosity LowCardinality(String),      -- heterozygous, homozygous
    allele_depth_ref UInt16,
    allele_depth_alt UInt16,
    read_depth UInt16,
    genotype_quality UInt8,               -- GQ
    phred_likelihood Array(UInt16),       -- PL

    -- 6. 집단 빈도 (Population Frequency) (12개)
    -- 6. Population Frequency (12 fields)
    af_gnomad_all Float32,
    af_gnomad_afr Float32,
    af_gnomad_amr Float32,
    af_gnomad_asj Float32,
    af_gnomad_eas Float32,
    af_gnomad_fin Float32,
    af_gnomad_nfe Float32,
    af_gnomad_sas Float32,
    af_1000g_all Float32,
    af_1000g_eas Float32,
    af_1000g_eur Float32,
    af_korean Float32,

    -- 7. ClinVar (임상 중요도) (5개)
    -- 7. ClinVar (Clinical Significance) (5 fields)
    clinvar_id String,
    clinvar_significance LowCardinality(String),
    clinvar_review_status LowCardinality(String),
    clinvar_disease String,
    clinvar_pmid Array(UInt32),

    -- 8. In-silico Prediction Scores (28개)
    -- 8. In-silico Prediction Scores (28 fields)
    sift_score Float32,
    sift_pred LowCardinality(String),
    polyphen2_score Float32,
    polyphen2_pred LowCardinality(String),
    cadd_phred Float32,
    cadd_raw Float32,
    revel_score Float32,
    dann_score Float32,
    fathmm_score Float32,
    fathmm_pred LowCardinality(String),
    metasvm_score Float32,
    metasvm_pred LowCardinality(String),
    metalr_score Float32,
    vest4_score Float32,
    provean_score Float32,
    provean_pred LowCardinality(String),
    mutationtaster_score Float32,
    mutationtaster_pred LowCardinality(String),
    mutationassessor_score Float32,
    lrt_score Float32,
    lrt_pred LowCardinality(String),
    primateai_score Float32,
    deogen2_score Float32,
    bayesdel_score Float32,
    clinpred_score Float32,
    list_s2_score Float32,
    m_cap_score Float32,
    m_cap_pred LowCardinality(String),

    -- 9. Conservation Scores (7개)
    -- 9. Conservation Scores (7 fields)
    phylop100way Float32,
    phylop30way Float32,
    phastcons100way Float32,
    phastcons30way Float32,
    gerp_rs Float32,
    gerp_n Float32,
    siphy_29way Float32,

    -- 10. Splicing Prediction (6개)
    -- 10. Splicing Prediction (6 fields)
    spliceai_score Float32,
    spliceai_pred LowCardinality(String),
    maxentscan_ref Float32,
    maxentscan_alt Float32,
    ada_score Float32,
    rf_score Float32,

    -- 11. Regulatory 정보 (3개)
    -- 11. Regulatory Information (3 fields)
    regulatory_feature LowCardinality(String),
    motif_name String,
    motif_score_change Float32,

    -- 12. 기타 데이터베이스 (3개)
    -- 12. Other Database References (3 fields)
    cosmic_id String,
    cosmic_count UInt32,
    icgc_id String,

    -- 13. 메타데이터 (12개)
    -- 13. Metadata (12 fields)
    annotation_source LowCardinality(String),
    annotation_version String,
    reference_genome LowCardinality(String),
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    custom_field_1 String DEFAULT '',
    custom_field_2 String DEFAULT '',
    custom_field_3 Float32 DEFAULT 0,
    custom_field_4 Float32 DEFAULT 0,
    custom_field_5 UInt32 DEFAULT 0
)
ENGINE = MergeTree()
PARTITION BY chromosome
ORDER BY (chromosome, position, sample_id)
SETTINGS index_granularity = 8192;

-- ================================================
-- Skip Indices
-- 스킵 인덱스
-- ================================================

-- Bloom Filter for gene (Point Query)
-- 유전자 Bloom Filter 인덱스 (정확한 검색)
ALTER TABLE genome.variants_full
ADD INDEX idx_gene gene TYPE bloom_filter GRANULARITY 4;

-- N-gram Bloom Filter for gene (Partial Match)
-- 유전자 N-gram Bloom Filter 인덱스 (부분 일치 검색)
ALTER TABLE genome.variants_full
ADD INDEX idx_gene_ngram gene TYPE ngrambf_v1(3, 65536, 3, 0) GRANULARITY 4;

-- Bloom Filter for sample_id
-- 샘플 ID Bloom Filter 인덱스
ALTER TABLE genome.variants_full
ADD INDEX idx_sample sample_id TYPE bloom_filter GRANULARITY 4;

-- Bloom Filter for clinical significance
-- 임상적 중요도 Bloom Filter 인덱스
ALTER TABLE genome.variants_full
ADD INDEX idx_clinvar_sig clinvar_significance TYPE bloom_filter GRANULARITY 4;

-- ================================================
-- Materialized View: gene_summary
-- 유전자별 변이 통계 사전 계산
-- Pre-computed Gene-level Variant Statistics
-- ================================================
CREATE MATERIALIZED VIEW genome.gene_summary
ENGINE = AggregatingMergeTree()
ORDER BY gene
AS SELECT
    gene,
    countState() AS total_variants,
    countIfState(impact = 'HIGH') AS high_impact_count,
    countIfState(impact = 'MODERATE') AS moderate_impact_count,
    countIfState(clinvar_significance = 'Pathogenic') AS pathogenic_count,
    avgState(cadd_phred) AS avg_cadd_phred,
    maxState(cadd_phred) AS max_cadd_phred
FROM genome.variants_full
GROUP BY gene;

-- ================================================
-- Projection: 샘플별 정렬 최적화
-- Projection: Sample-based Sorting Optimization
-- ================================================
ALTER TABLE genome.variants_full
    ADD PROJECTION proj_by_sample
    (SELECT * ORDER BY sample_id, chromosome, position);

-- Projection 구체화
-- Materialize Projection
ALTER TABLE genome.variants_full
    MATERIALIZE PROJECTION proj_by_sample;

-- ================================================
-- 테이블 정보 조회
-- Table Information Queries
-- ================================================

-- 스토리지 사이즈 확인
-- Check Storage Size
SELECT
    table,
    formatReadableSize(sum(bytes)) AS compressed_size,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(bytes), 2) AS compression_ratio
FROM system.parts
WHERE database = 'genome' AND table = 'variants_full' AND active
GROUP BY table;

-- 컬럼별 사이즈 확인
-- Check Column-wise Size
SELECT
    column,
    type,
    formatReadableSize(sum(column_bytes_on_disk)) AS size,
    formatReadableSize(avg(column_bytes_on_disk)) AS avg_size
FROM system.parts_columns
WHERE database = 'genome' AND table = 'variants_full' AND active
GROUP BY column, type
ORDER BY sum(column_bytes_on_disk) DESC
LIMIT 20;

-- 인덱스 사이즈 확인
-- Check Index Size
SELECT
    name,
    type,
    formatReadableSize(sum(secondary_index_compressed_bytes)) AS index_size,
    formatReadableSize(sum(secondary_index_uncompressed_bytes)) AS uncompressed_index_size
FROM system.parts
WHERE database = 'genome' AND table = 'variants_full' AND active
GROUP BY name, type
ORDER BY sum(secondary_index_compressed_bytes) DESC;
