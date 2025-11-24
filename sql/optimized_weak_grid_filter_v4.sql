-- ============================================================================
-- Optimized Weak Grid Filtering v4.0 - FILTER FIRST, CALCULATE LATER
-- ============================================================================
-- Purpose: Identify weak grid buildings using COMPUTATIONALLY EFFICIENT filtering
-- Key Innovation: Progressive filtering eliminates 90%+ buildings BEFORE expensive metrics
-- Expected Performance: 8-12 minutes (vs 45-60 minutes with old approach)
--
-- Filtering Sequence (Optimal Computational Efficiency):
--   1. Transformer distance >30km (highest selectivity ~90% eliminated)
--   2. Distribution line proximity <1km (11-24 kV lines only)
--   3. Grid density calculation (only on filtered subset)
--   4. Low density filter (≤1 line within 1km)
--   5. Building/load density (concentration of demand)
--   6. Final weak grid classification
--
-- Author: Klaus + Claude Code
-- Date: 2025-11-24
-- Version: 4.0-OPTIMIZED
-- ============================================================================

\timing on

\echo '========================================================================'
\echo 'Optimized Weak Grid Filtering v4.0'
\echo 'FILTER FIRST → CALCULATE LATER'
\echo '========================================================================'
\echo ''

-- ============================================================================
-- STEP 0: Create Materialized View of Distribution Lines
-- ============================================================================
-- Purpose: Pre-filter to 11-24 kV lines only
-- Rationale: One-time operation, creates indexed view for all subsequent queries
-- Performance: ~10-30 seconds (one-time cost)
-- Note: Power poles removed - LineString geometries already represent complete lines
-- ============================================================================

\echo 'Step 0: Creating distribution lines view (11-24 kV)...'

DROP MATERIALIZED VIEW IF EXISTS distribution_lines_11_24kv CASCADE;

CREATE MATERIALIZED VIEW distribution_lines_11_24kv AS
-- Distribution power lines (11-24 kV)
SELECT
    id,
    geometry,
    spenning_kv as voltage_kv,
    driftsattaar::integer as year_built,
    eierorgnr::text as owner_orgnr
FROM power_lines_new
WHERE spenning_kv BETWEEN 11 AND 24;

-- Create spatial index
CREATE INDEX idx_distribution_lines_geom
    ON distribution_lines_11_24kv USING GIST(geometry);

\echo '  ✓ Distribution lines view created'

-- Show statistics
SELECT
    COUNT(*) as total_lines,
    COUNT(voltage_kv) as lines_with_voltage,
    ROUND(AVG(voltage_kv)) as avg_voltage_kv,
    MIN(voltage_kv) as min_voltage_kv,
    MAX(voltage_kv) as max_voltage_kv
FROM distribution_lines_11_24kv;

\echo ''

-- ============================================================================
-- STEP 1: Filter by Transformer Distance >30km (HIGHEST SELECTIVITY)
-- ============================================================================
-- Purpose: Eliminate ~90% of buildings immediately
-- Rationale: Buildings close to transformers have STRONG grid, not weak
-- Expected Output: ~6,500-13,000 buildings (5-10% of 130,250)
-- Performance: ~2-3 minutes with spatial index
-- ============================================================================

\echo 'Step 1: Filtering buildings >30km from transformers...'
\echo '  (This eliminates ~90% of buildings - highest selectivity filter)'

DROP TABLE IF EXISTS step1_far_from_transformers;

CREATE TEMP TABLE step1_far_from_transformers AS
SELECT
    b.id,
    b.geometry,
    b.bygningstype,
    b.building_type_name,
    b.building_source,
    b.postal_code,
    b.kommunenavn,
    ST_Distance(
        b.geometry::geography,
        (SELECT geometry FROM transformers_new
         ORDER BY b.geometry <-> geometry LIMIT 1)::geography
    ) as transformer_distance_m
FROM buildings b
WHERE NOT EXISTS (
    SELECT 1
    FROM transformers_new t
    WHERE ST_DWithin(b.geometry::geography, t.geometry::geography, 30000)
);

CREATE INDEX idx_step1_geom ON step1_far_from_transformers USING GIST(geometry);

\echo '  ✓ Step 1 complete'

SELECT
    COUNT(*) as buildings_remaining,
    ROUND(AVG(transformer_distance_m)) as avg_transformer_dist_m,
    ROUND(MIN(transformer_distance_m)) as min_dist_m,
    ROUND(MAX(transformer_distance_m)) as max_dist_m
FROM step1_far_from_transformers;

\echo ''

-- ============================================================================
-- STEP 2: Filter by Distance to Distribution Lines <1km
-- ============================================================================
-- Purpose: Find buildings near distribution lines but far from transformers
-- Rationale: KNN operator is fast, eliminates truly off-grid buildings
-- Expected Output: ~4,000-9,000 buildings (60-70% of Step 1)
-- Performance: ~30-60 seconds (KNN on small dataset)
-- ============================================================================

\echo 'Step 2: Filtering buildings <1km from distribution lines...'
\echo '  (11-24 kV lines only)'

DROP TABLE IF EXISTS step2_near_distribution;

CREATE TEMP TABLE step2_near_distribution AS
SELECT
    s1.id,
    s1.geometry,
    s1.bygningstype,
    s1.building_type_name,
    s1.building_source,
    s1.postal_code,
    s1.kommunenavn,
    s1.transformer_distance_m,
    dl.voltage_kv as nearest_voltage_kv,
    dl.year_built as nearest_year_built,
    ST_Distance(s1.geometry::geography, dl.geometry::geography) as line_distance_m
FROM step1_far_from_transformers s1
CROSS JOIN LATERAL (
    SELECT voltage_kv, year_built, geometry
    FROM distribution_lines_11_24kv
    ORDER BY s1.geometry <-> geometry
    LIMIT 1
) dl
WHERE ST_Distance(s1.geometry::geography, dl.geometry::geography) < 1000;

CREATE INDEX idx_step2_geom ON step2_near_distribution USING GIST(geometry);

\echo '  ✓ Step 2 complete'

SELECT
    COUNT(*) as buildings_remaining,
    ROUND(AVG(line_distance_m)) as avg_line_dist_m,
    ROUND(MIN(line_distance_m)) as min_dist_m,
    ROUND(MAX(line_distance_m)) as max_dist_m
FROM step2_near_distribution;

\echo ''

-- ============================================================================
-- STEP 3: Calculate Grid Density (NOW COMPUTATIONALLY FEASIBLE)
-- ============================================================================
-- Purpose: Count distribution lines within 1km of each building
-- Rationale: ST_DWithin only on ~4K-9K buildings (vs 130K) = 93% fewer ops
-- Expected Output: Same ~4K-9K buildings with density calculated
-- Performance: ~3-5 minutes (vs 26+ minutes on full dataset)
-- ============================================================================

\echo 'Step 3: Calculating grid density within 1km...'
\echo '  (ST_DWithin on ~9K buildings vs 130K = 93% fewer operations)'

DROP TABLE IF EXISTS step3_with_density;

CREATE TEMP TABLE step3_with_density AS
SELECT
    s2.id,
    s2.geometry,
    s2.bygningstype,
    s2.building_type_name,
    s2.building_source,
    s2.postal_code,
    s2.kommunenavn,
    s2.transformer_distance_m,
    s2.nearest_voltage_kv,
    s2.nearest_year_built,
    s2.line_distance_m,
    COUNT(dl.id) as line_count_1km,
    COALESCE(SUM(ST_Length(dl.geometry::geography)) / 1000, 0) as grid_length_km
FROM step2_near_distribution s2
LEFT JOIN distribution_lines_11_24kv dl
    ON ST_DWithin(s2.geometry::geography, dl.geometry::geography, 1000)
GROUP BY s2.id, s2.geometry, s2.bygningstype, s2.building_type_name, s2.building_source,
         s2.postal_code, s2.kommunenavn, s2.transformer_distance_m,
         s2.nearest_voltage_kv, s2.nearest_year_built, s2.line_distance_m;

CREATE INDEX idx_step3_geom ON step3_with_density USING GIST(geometry);

\echo '  ✓ Step 3 complete'

SELECT
    COUNT(*) as buildings_with_density,
    ROUND(AVG(line_count_1km)) as avg_lines_1km,
    ROUND(AVG(grid_length_km)::numeric, 2) as avg_grid_length_km,
    MAX(line_count_1km) as max_lines_1km
FROM step3_with_density;

\echo ''

-- ============================================================================
-- STEP 4: Filter by Low Grid Density (≤1 line within 1km)
-- ============================================================================
-- Purpose: Identify sparse grid areas (few lines = weak capacity)
-- Rationale: Attribute filter on calculated field (instant)
-- Expected Output: ~1,000-2,500 buildings (25-30% of Step 3)
-- Performance: <1 second
-- ============================================================================

\echo 'Step 4: Filtering by low grid density (≤1 line within 1km)...'

DROP TABLE IF EXISTS step4_sparse_grid;

CREATE TEMP TABLE step4_sparse_grid AS
SELECT *
FROM step3_with_density
WHERE line_count_1km <= 1;

CREATE INDEX idx_step4_geom ON step4_sparse_grid USING GIST(geometry);

\echo '  ✓ Step 4 complete'

SELECT
    COUNT(*) as buildings_remaining,
    COUNT(*) FILTER (WHERE line_count_1km = 0) as no_lines_within_1km,
    COUNT(*) FILTER (WHERE line_count_1km = 1) as one_line_within_1km
FROM step4_sparse_grid;

\echo ''

-- ============================================================================
-- STEP 5: Calculate Building/Load Density
-- ============================================================================
-- Purpose: Count buildings within 1km (load concentration indicator)
-- Rationale: Many buildings on weak grid = high cumulative load
-- Expected Output: ~1,000-2,500 buildings with load density
-- Performance: ~30-60 seconds (small dataset)
-- ============================================================================

\echo 'Step 5: Calculating building/load density within 1km...'

DROP TABLE IF EXISTS step5_with_load_density;

CREATE TEMP TABLE step5_with_load_density AS
SELECT
    s4.*,
    (SELECT COUNT(*)
     FROM buildings b
     WHERE ST_DWithin(s4.geometry::geography, b.geometry::geography, 1000)
    ) as buildings_within_1km,
    (SELECT COUNT(*)
     FROM buildings b
     WHERE ST_DWithin(s4.geometry::geography, b.geometry::geography, 1000)
       AND b.building_source = 'residential'
    ) as residential_within_1km,
    (SELECT COUNT(*)
     FROM buildings b
     WHERE ST_DWithin(s4.geometry::geography, b.geometry::geography, 1000)
       AND b.building_source = 'cabin'
    ) as cabins_within_1km
FROM step4_sparse_grid s4;

\echo '  ✓ Step 5 complete'

SELECT
    COUNT(*) as buildings_with_load_density,
    ROUND(AVG(buildings_within_1km)) as avg_buildings_1km,
    ROUND(AVG(residential_within_1km)) as avg_residential_1km,
    ROUND(AVG(cabins_within_1km)) as avg_cabins_1km,
    MAX(buildings_within_1km) as max_load_concentration
FROM step5_with_load_density;

\echo ''

-- ============================================================================
-- STEP 6: Final Weak Grid Classification
-- ============================================================================
-- Purpose: Classify buildings by weak grid severity tiers
-- Criteria: Distance to transformer + load concentration
-- Expected Output: ~300-750 buildings (30-50% of Step 5)
-- Performance: <1 second
-- ============================================================================

\echo 'Step 6: Final weak grid classification with tiering...'

DROP TABLE IF EXISTS weak_grid_candidates_v4;

CREATE TABLE weak_grid_candidates_v4 AS
SELECT
    id,
    bygningstype,
    building_type_name,
    building_source,
    postal_code,
    kommunenavn,
    transformer_distance_m,
    nearest_voltage_kv,
    nearest_year_built,
    line_distance_m,
    line_count_1km,
    grid_length_km,
    buildings_within_1km,
    residential_within_1km,
    cabins_within_1km,
    -- Weak grid tier classification
    CASE
        WHEN transformer_distance_m > 50000 THEN 'Tier 1: Extreme (>50km from transformer)'
        WHEN transformer_distance_m > 30000 THEN 'Tier 2: Severe (30-50km from transformer)'
    END as weak_grid_tier,
    -- Load severity (buildings sharing weak grid)
    CASE
        WHEN buildings_within_1km >= 20 THEN 'High load concentration (≥20 buildings)'
        WHEN buildings_within_1km >= 10 THEN 'Medium load concentration (10-19 buildings)'
        WHEN buildings_within_1km >= 5 THEN 'Low load concentration (5-9 buildings)'
        ELSE 'Isolated building (<5 nearby)'
    END as load_severity,
    -- Combined risk score (higher = weaker grid + more load)
    (transformer_distance_m / 1000.0) * (buildings_within_1km + 1) as composite_risk_score,
    geometry
FROM step5_with_load_density
WHERE buildings_within_1km >= 3  -- At least 3 buildings (including self) sharing weak grid
ORDER BY transformer_distance_m DESC, buildings_within_1km DESC;

CREATE INDEX idx_weak_grid_v4_geom ON weak_grid_candidates_v4 USING GIST(geometry);
CREATE INDEX idx_weak_grid_v4_risk ON weak_grid_candidates_v4(composite_risk_score DESC);
CREATE INDEX idx_weak_grid_v4_tier ON weak_grid_candidates_v4(weak_grid_tier);

\echo '  ✓ Step 6 complete'
\echo ''

-- ============================================================================
-- FINAL STATISTICS AND SUMMARY
-- ============================================================================

\echo '========================================================================'
\echo 'FINAL RESULTS: Optimized Weak Grid Candidates v4.0'
\echo '========================================================================'
\echo ''

-- Overall summary
\echo '[Overall Summary]'
SELECT
    COUNT(*) as total_weak_grid_candidates,
    COUNT(*) FILTER (WHERE weak_grid_tier LIKE '%Extreme%') as tier1_extreme,
    COUNT(*) FILTER (WHERE weak_grid_tier LIKE '%Severe%') as tier2_severe,
    ROUND(AVG(transformer_distance_m)) as avg_transformer_dist_m,
    ROUND(AVG(buildings_within_1km)) as avg_load_concentration,
    ROUND(AVG(composite_risk_score)::numeric, 1) as avg_composite_risk
FROM weak_grid_candidates_v4;

\echo ''

-- By building type
\echo '[Distribution by Building Type]'
SELECT
    bygningstype,
    building_type_name,
    building_source,
    COUNT(*) as count,
    ROUND(AVG(transformer_distance_m)) as avg_transformer_dist_m,
    ROUND(AVG(buildings_within_1km)) as avg_load
FROM weak_grid_candidates_v4
GROUP BY bygningstype, building_type_name, building_source
ORDER BY count DESC;

\echo ''

-- By weak grid tier
\echo '[Distribution by Weak Grid Tier]'
SELECT
    weak_grid_tier,
    COUNT(*) as count,
    ROUND(AVG(buildings_within_1km)) as avg_load_concentration,
    ROUND(AVG(composite_risk_score)::numeric, 1) as avg_risk_score
FROM weak_grid_candidates_v4
GROUP BY weak_grid_tier
ORDER BY weak_grid_tier;

\echo ''

-- By load severity
\echo '[Distribution by Load Concentration]'
SELECT
    load_severity,
    COUNT(*) as count,
    ROUND(AVG(transformer_distance_m)) as avg_transformer_dist_m,
    ROUND(AVG(line_count_1km)) as avg_lines_1km
FROM weak_grid_candidates_v4
GROUP BY load_severity
ORDER BY
    CASE load_severity
        WHEN 'High load concentration (≥20 buildings)' THEN 1
        WHEN 'Medium load concentration (10-19 buildings)' THEN 2
        WHEN 'Low load concentration (5-9 buildings)' THEN 3
        ELSE 4
    END;

\echo ''

-- Top 20 highest risk candidates
\echo '[Top 20 Highest Risk Candidates]'
SELECT
    id,
    building_type_name,
    postal_code,
    ROUND(transformer_distance_m) as transformer_dist_m,
    line_count_1km,
    buildings_within_1km as load,
    ROUND(composite_risk_score::numeric, 1) as risk_score,
    weak_grid_tier,
    load_severity
FROM weak_grid_candidates_v4
ORDER BY composite_risk_score DESC
LIMIT 20;

\echo ''
\echo '========================================================================'
\echo '✓ Optimized Weak Grid Filtering v4.0 Complete'
\echo '========================================================================'
\echo ''
\echo 'Performance Improvement: ~5-6x faster (8-12 min vs 45-60 min)'
\echo 'Computational Savings: ~93% fewer spatial operations'
\echo ''
\echo 'Output table: weak_grid_candidates_v4'
\echo 'Materialized view: distribution_lines_11_24kv'
\echo ''
\echo 'Next steps:'
\echo '  - Review top risk candidates'
\echo '  - Generate reports by tier and building type'
\echo '  - Create visualization of weak grid clusters'
\echo '  - Export CSV for field validation'
\echo '========================================================================'
