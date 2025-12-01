-- ================================================
-- 샘플 데이터 생성 (30억건)
-- Sample Data Generation (3 Billion Rows)
-- ================================================

-- ================================================
-- 1. 데이터 생성 쿼리
-- 1. Data Generation Query
-- ================================================
INSERT INTO genome.variants_full
SELECT
    -- 1. 위치 및 기본 변이 정보
    -- 1. Position and Basic Variant Information
    arrayElement(['chr1', 'chr2', 'chr3', 'chr4', 'chr5', 'chr6', 'chr7', 'chr8',
                  'chr9', 'chr10', 'chr11', 'chr12', 'chr13', 'chr14', 'chr15',
                  'chr16', 'chr17', 'chr18', 'chr19', 'chr20', 'chr21', 'chr22',
                  'chrX', 'chrY'], (number % 24) + 1) AS chromosome,
    (number % 250000000) + 1 AS position,
    arrayElement(['A', 'C', 'G', 'T'], (number % 4) + 1) AS ref,
    arrayElement(['A', 'C', 'G', 'T'], ((number + 1) % 4) + 1) AS alt,
    concat('rs', toString(number % 1000000000)) AS variant_id,
    if(number % 10 = 0, 'InDel', 'SNP') AS variant_type,
    (rand() % 1000) / 10.0 AS quality,
    if(rand() % 20 = 0, 'LowQual', 'PASS') AS filter,

    -- 2. 유전자 및 전사체 정보
    -- 2. Gene and Transcript Information
    arrayElement([
        'BRCA1', 'BRCA2', 'TP53', 'EGFR', 'KRAS', 'PIK3CA', 'PTEN', 'BRAF',
        'MYC', 'ERBB2', 'APC', 'ATM', 'CDH1', 'CDKN2A', 'FGFR2', 'GATA3',
        'MAP3K1', 'NCOR1', 'PIK3R1', 'RB1', 'RUNX1', 'SMAD4', 'STK11', 'TBX3',
        'ALK', 'RET', 'MET', 'NRAS', 'HRAS', 'KIT', 'PDGFRA', 'FLT3',
        'JAK2', 'ABL1', 'SRC', 'NOTCH1', 'NOTCH2', 'NOTCH3', 'WNT', 'CTNNB1'
    ], (number % 40) + 1) AS gene,
    concat('ENSG', lpad(toString(number % 100000), 11, '0')) AS gene_id,
    concat('ENST', lpad(toString(number % 200000), 11, '0')) AS transcript_id,
    arrayElement(['protein_coding', 'lincRNA', 'miRNA', 'processed_transcript'],
                 (number % 4) + 1) AS transcript_biotype,
    (number % 50) + 1 AS exon_number,
    (number % 50) + 1 AS intron_number,

    -- 3. 기능적 영향
    -- 3. Functional Impact
    arrayElement(['HIGH', 'MODERATE', 'LOW', 'MODIFIER'], (number % 4) + 1) AS impact,
    arrayElement([
        'missense_variant', 'synonymous_variant', 'stop_gained', 'frameshift_variant',
        'splice_donor_variant', 'splice_acceptor_variant', 'start_lost', 'stop_lost',
        'inframe_insertion', 'inframe_deletion', 'intron_variant', 'upstream_variant'
    ], (number % 12) + 1) AS consequence,
    concat('c.', toString((number % 10000) + 1), 'A>G') AS hgvs_c,
    concat('p.', arrayElement(['Ala', 'Arg', 'Asn', 'Asp', 'Cys', 'Gln', 'Glu', 'Gly'],
                              (number % 8) + 1), toString((number % 1000) + 1), 'Val') AS hgvs_p,
    concat(arrayElement(['ATG', 'GCT', 'TTA', 'CCG'], (number % 4) + 1), '/',
           arrayElement(['ATC', 'GCC', 'TTG', 'CCA'], (number % 4) + 1)) AS codon_change,
    concat(arrayElement(['A', 'R', 'N', 'D', 'C', 'Q', 'E', 'G'], (number % 8) + 1),
           toString((number % 1000) + 1),
           arrayElement(['V', 'L', 'I', 'M', 'F', 'Y', 'W'], (number % 7) + 1)) AS amino_acid_change,
    (number % 2000) + 1 AS protein_position,

    -- 4. 샘플 정보
    -- 4. Sample Information
    concat('SAMPLE_', lpad(toString(number % 100000), 6, '0')) AS sample_id,
    arrayElement(['germline', 'tumor', 'normal'], (number % 3) + 1) AS sample_type,
    arrayElement(['blood', 'tissue', 'saliva', 'biopsy'], (number % 4) + 1) AS tissue_type,
    toDate('2020-01-01') + toIntervalDay(number % 1825) AS collection_date,

    -- 5. Genotype 정보
    -- 5. Genotype Information
    arrayElement(['0/0', '0/1', '1/1', '0/2', '1/2'], (number % 5) + 1) AS genotype,
    if((number % 5) = 2, 'homozygous', 'heterozygous') AS zygosity,
    (number % 100) + 10 AS allele_depth_ref,
    (number % 100) + 10 AS allele_depth_alt,
    (number % 200) + 20 AS read_depth,
    (number % 99) + 1 AS genotype_quality,
    [(number % 100), ((number + 1) % 100), ((number + 2) % 100)] AS phred_likelihood,

    -- 6. 집단 빈도
    -- 6. Population Frequency
    (rand() % 1000000) / 1000000.0 AS af_gnomad_all,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_afr,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_amr,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_asj,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_eas,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_fin,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_nfe,
    (rand() % 1000000) / 1000000.0 AS af_gnomad_sas,
    (rand() % 1000000) / 1000000.0 AS af_1000g_all,
    (rand() % 1000000) / 1000000.0 AS af_1000g_eas,
    (rand() % 1000000) / 1000000.0 AS af_1000g_eur,
    (rand() % 1000000) / 1000000.0 AS af_korean,

    -- 7. ClinVar
    -- 7. ClinVar
    if(number % 100 < 5, concat('VCV', toString(number % 1000000)), '') AS clinvar_id,
    arrayElement(['Pathogenic', 'Likely_pathogenic', 'Uncertain_significance',
                  'Likely_benign', 'Benign', ''], (number % 6) + 1) AS clinvar_significance,
    arrayElement(['reviewed_by_expert_panel', 'criteria_provided', 'no_assertion', ''],
                 (number % 4) + 1) AS clinvar_review_status,
    if(number % 100 < 5,
       arrayElement(['Breast cancer', 'Colorectal cancer', 'Lung cancer', 'Melanoma'],
                    (number % 4) + 1), '') AS clinvar_disease,
    if(number % 100 < 5, [20000000 + (number % 10000000)], []) AS clinvar_pmid,

    -- 8. In-silico Prediction Scores
    -- 8. In-silico Prediction Scores
    (rand() % 100) / 100.0 AS sift_score,
    arrayElement(['deleterious', 'tolerated', ''], (number % 3) + 1) AS sift_pred,
    (rand() % 100) / 100.0 AS polyphen2_score,
    arrayElement(['probably_damaging', 'possibly_damaging', 'benign', ''],
                 (number % 4) + 1) AS polyphen2_pred,
    (rand() % 4000) / 100.0 AS cadd_phred,
    (rand() % 700) / 100.0 - 3.5 AS cadd_raw,
    (rand() % 100) / 100.0 AS revel_score,
    (rand() % 100) / 100.0 AS dann_score,
    (rand() % 1400) / 100.0 - 7.0 AS fathmm_score,
    arrayElement(['DAMAGING', 'TOLERATED', ''], (number % 3) + 1) AS fathmm_pred,
    (rand() % 200) / 100.0 - 1.0 AS metasvm_score,
    arrayElement(['D', 'T', ''], (number % 3) + 1) AS metasvm_pred,
    (rand() % 100) / 100.0 AS metalr_score,
    (rand() % 100) / 100.0 AS vest4_score,
    (rand() % 2800) / 100.0 - 14.0 AS provean_score,
    arrayElement(['deleterious', 'neutral', ''], (number % 3) + 1) AS provean_pred,
    (rand() % 100) / 100.0 AS mutationtaster_score,
    arrayElement(['disease_causing', 'polymorphism', ''], (number % 3) + 1) AS mutationtaster_pred,
    (rand() % 700) / 100.0 AS mutationassessor_score,
    (rand() % 100) / 100.0 AS lrt_score,
    arrayElement(['D', 'N', 'U'], (number % 3) + 1) AS lrt_pred,
    (rand() % 100) / 100.0 AS primateai_score,
    (rand() % 100) / 100.0 AS deogen2_score,
    (rand() % 200) / 100.0 - 1.0 AS bayesdel_score,
    (rand() % 100) / 100.0 AS clinpred_score,
    (rand() % 100) / 100.0 AS list_s2_score,
    (rand() % 100) / 100.0 AS m_cap_score,
    arrayElement(['D', 'T', ''], (number % 3) + 1) AS m_cap_pred,

    -- 9. Conservation Scores
    -- 9. Conservation Scores
    (rand() % 2000) / 100.0 - 10.0 AS phylop100way,
    (rand() % 2000) / 100.0 - 10.0 AS phylop30way,
    (rand() % 100) / 100.0 AS phastcons100way,
    (rand() % 100) / 100.0 AS phastcons30way,
    (rand() % 1200) / 100.0 - 6.0 AS gerp_rs,
    (rand() % 600) / 100.0 AS gerp_n,
    (rand() % 3000) / 100.0 AS siphy_29way,

    -- 10. Splicing Prediction
    -- 10. Splicing Prediction
    (rand() % 100) / 100.0 AS spliceai_score,
    arrayElement(['splice_donor', 'splice_acceptor', 'splice_region', ''],
                 (number % 4) + 1) AS spliceai_pred,
    (rand() % 2000) / 100.0 - 10.0 AS maxentscan_ref,
    (rand() % 2000) / 100.0 - 10.0 AS maxentscan_alt,
    (rand() % 100) / 100.0 AS ada_score,
    (rand() % 100) / 100.0 AS rf_score,

    -- 11. Regulatory
    -- 11. Regulatory Information
    arrayElement(['promoter', 'enhancer', 'TF_binding_site', ''], (number % 4) + 1) AS regulatory_feature,
    if(number % 50 = 0, concat('MOTIF_', toString(number % 10000)), '') AS motif_name,
    (rand() % 200) / 100.0 - 1.0 AS motif_score_change,

    -- 12. 기타 데이터베이스
    -- 12. Other Database References
    if(number % 200 < 5, concat('COSV', toString(number % 10000000)), '') AS cosmic_id,
    if(number % 200 < 5, (number % 100) + 1, 0) AS cosmic_count,
    if(number % 300 < 3, concat('MU', toString(number % 1000000)), '') AS icgc_id,

    -- 13. 메타데이터
    -- 13. Metadata
    arrayElement(['VEP', 'ANNOVAR', 'SnpEff'], (number % 3) + 1) AS annotation_source,
    arrayElement(['v104', 'v105', 'v106'], (number % 3) + 1) AS annotation_version,
    'GRCh38' AS reference_genome,
    now() - toIntervalDay(number % 365) AS created_at,
    now() - toIntervalDay(number % 30) AS updated_at,
    '' AS custom_field_1,
    '' AS custom_field_2,
    0 AS custom_field_3,
    0 AS custom_field_4,
    0 AS custom_field_5
FROM numbers(3000000000);  -- 30억건 생성 / Generate 3 billion rows
