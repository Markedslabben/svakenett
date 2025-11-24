-- ============================================================================
-- Calculate Cabin-to-Grid Distance Metrics
-- ============================================================================
-- Purpose: Enrich cabins table with grid infrastructure proximity data
-- Dependencies: nve_power_lines, nve_transformers tables must be loaded
-- Author: Klaus
-- Date: 2025-01-22
-- ============================================================================

\echo '========================================'
\echo 'Calculating Cabin Grid Distance Metrics'
\echo '========================================'

-- ============================================================================
-- STEP 1: Calculate Distance to Nearest Power Line
-- ============================================================================
-- Process in batches to avoid memory issues with large cabin datasets
-- Only consider distribution-level lines (nve_nett_nivaa = 3)
-- ============================================================================

\echo ''
\echo '[1/4] Calculating distance to nearest power line (batch processing)...'

-- Batch 1: Cabins 1-5000
UPDATE cabins c
SET
    distance_to_line_m = subq.distance_m,
    nearest_line_id = subq.line_id,
    nearest_line_voltage_kv = subq.voltage_kv,
    nearest_line_age_years = subq.age_years
FROM (
    SELECT DISTINCT ON (c.id)
        c.id as cabin_id,
        pl.id as line_id,
        pl.spenning_kv as voltage_kv,
        pl.alder_aar as age_years,
        ST_Distance(
            c.geometry::geography,
            pl.geometry::geography
        ) as distance_m
    FROM cabins c
    CROSS JOIN LATERAL (
        SELECT
            id,
            spenning_kv,
            alder_aar,
            geometry
        FROM nve_power_lines
        WHERE nve_nett_nivaa = 3  -- Distribution grid only
        ORDER BY c.geometry <-> geometry
        LIMIT 1
    ) pl
    WHERE c.id >= 1 AND c.id < 5000
) subq
WHERE c.id = subq.cabin_id;

\echo '  ✓ Batch 1 complete (cabins 1-4999)'

-- Batch 2: Cabins 5000-10000
UPDATE cabins c
SET
    distance_to_line_m = subq.distance_m,
    nearest_line_id = subq.line_id,
    nearest_line_voltage_kv = subq.voltage_kv,
    nearest_line_age_years = subq.age_years
FROM (
    SELECT DISTINCT ON (c.id)
        c.id as cabin_id,
        pl.id as line_id,
        pl.spenning_kv as voltage_kv,
        pl.alder_aar as age_years,
        ST_Distance(
            c.geometry::geography,
            pl.geometry::geography
        ) as distance_m
    FROM cabins c
    CROSS JOIN LATERAL (
        SELECT
            id,
            spenning_kv,
            alder_aar,
            geometry
        FROM nve_power_lines
        WHERE nve_nett_nivaa = 3
        ORDER BY c.geometry <-> geometry
        LIMIT 1
    ) pl
    WHERE c.id >= 5000 AND c.id < 10000
) subq
WHERE c.id = subq.cabin_id;

\echo '  ✓ Batch 2 complete (cabins 5000-9999)'

-- Batch 3: Remaining cabins (10000+)
UPDATE cabins c
SET
    distance_to_line_m = subq.distance_m,
    nearest_line_id = subq.line_id,
    nearest_line_voltage_kv = subq.voltage_kv,
    nearest_line_age_years = subq.age_years
FROM (
    SELECT DISTINCT ON (c.id)
        c.id as cabin_id,
        pl.id as line_id,
        pl.spenning_kv as voltage_kv,
        pl.alder_aar as age_years,
        ST_Distance(
            c.geometry::geography,
            pl.geometry::geography
        ) as distance_m
    FROM cabins c
    CROSS JOIN LATERAL (
        SELECT
            id,
            spenning_kv,
            alder_aar,
            geometry
        FROM nve_power_lines
        WHERE nve_nett_nivaa = 3
        ORDER BY c.geometry <-> geometry
        LIMIT 1
    ) pl
    WHERE c.id >= 10000
) subq
WHERE c.id = subq.cabin_id;

\echo '  ✓ Batch 3 complete (cabins 10000+)'

-- Show distance statistics
\echo ''
\echo '[Distance Statistics]'
SELECT
    'Distance to Line' as metric,
    COUNT(*) as cabins,
    ROUND(MIN(distance_to_line_m), 0) as min_m,
    ROUND(AVG(distance_to_line_m), 0) as avg_m,
    ROUND(MAX(distance_to_line_m), 0) as max_m,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_to_line_m), 0) as median_m
FROM cabins
WHERE distance_to_line_m IS NOT NULL;

-- ============================================================================
-- STEP 2: Calculate Grid Density (lines within 1km radius)
-- ============================================================================
-- Count and measure total length of power lines within 1km of each cabin
-- ============================================================================

\echo ''
\echo '[2/4] Calculating grid density within 1km radius (batch processing)...'

-- Batch 1: Cabins 1-5000
UPDATE cabins c
SET
    grid_density_1km = subq.line_count,
    grid_line_length_1km_m = subq.total_length_m
FROM (
    SELECT
        c.id,
        COUNT(pl.id) as line_count,
        COALESCE(SUM(ST_Length(pl.geometry::geography)), 0) as total_length_m
    FROM cabins c
    LEFT JOIN nve_power_lines pl
        ON ST_DWithin(
            c.geometry::geography,
            pl.geometry::geography,
            1000  -- 1km buffer
        )
        AND pl.nve_nett_nivaa = 3
    WHERE c.id >= 1 AND c.id < 5000
    GROUP BY c.id
) subq
WHERE c.id = subq.id;

\echo '  ✓ Batch 1 complete (cabins 1-4999)'

-- Batch 2: Cabins 5000-10000
UPDATE cabins c
SET
    grid_density_1km = subq.line_count,
    grid_line_length_1km_m = subq.total_length_m
FROM (
    SELECT
        c.id,
        COUNT(pl.id) as line_count,
        COALESCE(SUM(ST_Length(pl.geometry::geography)), 0) as total_length_m
    FROM cabins c
    LEFT JOIN nve_power_lines pl
        ON ST_DWithin(
            c.geometry::geography,
            pl.geometry::geography,
            1000
        )
        AND pl.nve_nett_nivaa = 3
    WHERE c.id >= 5000 AND c.id < 10000
    GROUP BY c.id
) subq
WHERE c.id = subq.id;

\echo '  ✓ Batch 2 complete (cabins 5000-9999)'

-- Batch 3: Remaining cabins
UPDATE cabins c
SET
    grid_density_1km = subq.line_count,
    grid_line_length_1km_m = subq.total_length_m
FROM (
    SELECT
        c.id,
        COUNT(pl.id) as line_count,
        COALESCE(SUM(ST_Length(pl.geometry::geography)), 0) as total_length_m
    FROM cabins c
    LEFT JOIN nve_power_lines pl
        ON ST_DWithin(
            c.geometry::geography,
            pl.geometry::geography,
            1000
        )
        AND pl.nve_nett_nivaa = 3
    WHERE c.id >= 10000
    GROUP BY c.id
) subq
WHERE c.id = subq.id;

\echo '  ✓ Batch 3 complete (cabins 10000+)'

-- Show density statistics
\echo ''
\echo '[Grid Density Statistics]'
SELECT
    'Lines within 1km' as metric,
    COUNT(*) as cabins,
    MIN(grid_density_1km) as min_lines,
    ROUND(AVG(grid_density_1km), 1) as avg_lines,
    MAX(grid_density_1km) as max_lines,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY grid_density_1km) as median_lines
FROM cabins
WHERE grid_density_1km IS NOT NULL;

-- ============================================================================
-- STEP 3: Calculate Distance to Nearest Transformer
-- ============================================================================
-- Proximity to transformer indicates grid capacity and supply stability
-- ============================================================================

\echo ''
\echo '[3/4] Calculating distance to nearest transformer...'

UPDATE cabins c
SET nearest_transformer_m = subq.distance_m
FROM (
    SELECT DISTINCT ON (c.id)
        c.id as cabin_id,
        ST_Distance(
            c.geometry::geography,
            t.geometry::geography
        ) as distance_m
    FROM cabins c
    CROSS JOIN LATERAL (
        SELECT geometry
        FROM nve_transformers
        ORDER BY c.geometry <-> geometry
        LIMIT 1
    ) t
) subq
WHERE c.id = subq.cabin_id;

\echo '  ✓ Transformer distances calculated'

-- Show transformer distance statistics
\echo ''
\echo '[Transformer Distance Statistics]'
SELECT
    'Distance to Transformer' as metric,
    COUNT(*) as cabins,
    ROUND(MIN(nearest_transformer_m), 0) as min_m,
    ROUND(AVG(nearest_transformer_m), 0) as avg_m,
    ROUND(MAX(nearest_transformer_m), 0) as max_m,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nearest_transformer_m), 0) as median_m
FROM cabins
WHERE nearest_transformer_m IS NOT NULL;

-- ============================================================================
-- STEP 4: Validation Summary
-- ============================================================================

\echo ''
\echo '[4/4] Validation Summary'
\echo ''

SELECT
    'Total Cabins' as metric,
    COUNT(*)::text as value
FROM cabins
UNION ALL
SELECT
    'With Distance Data',
    COUNT(*)::text
FROM cabins
WHERE distance_to_line_m IS NOT NULL
UNION ALL
SELECT
    'With Density Data',
    COUNT(*)::text
FROM cabins
WHERE grid_density_1km IS NOT NULL
UNION ALL
SELECT
    'Average Distance to Line (m)',
    ROUND(AVG(distance_to_line_m), 0)::text
FROM cabins
WHERE distance_to_line_m IS NOT NULL
UNION ALL
SELECT
    'Average Grid Density (lines/km²)',
    ROUND(AVG(grid_density_1km), 1)::text
FROM cabins
WHERE grid_density_1km IS NOT NULL;

\echo ''
\echo '========================================'
\echo '✓ Cabin Grid Distance Calculations Complete'
\echo '========================================'
\echo ''
\echo 'Next step: Calculate weak grid scores'
\echo '  psql $DATABASE_URL -f scripts/calculate_weak_grid_scores.sql'
\echo ''
