-- ============================================================================
-- Calculate Weak Grid Composite Scores v3.0 (SIMPLIFIED - without transformer data)
-- ============================================================================
-- Purpose: Apply infrastructure-based scoring (NO KILE, NO transformer distance)
-- Score range: 0-100 (higher = weaker grid = better prospect)
-- Dependencies: cabins table with basic grid metrics
-- Author: Klaus
-- Date: 2025-11-24
-- Version: 3.0-SIMPLIFIED (uses only available data: distance_to_line, density, voltage, age)
-- ============================================================================

\echo '========================================'
\echo 'Calculating Weak Grid Scores v3.0'
\echo 'SIMPLIFIED - Using Available Data Only'
\echo '========================================'

-- Reset all scores first
UPDATE cabins SET weak_grid_score = NULL;

-- Apply v3.0 scoring with available data
UPDATE cabins
SET weak_grid_score = (
    -- ========================================================================
    -- FACTOR 1: Distance to Power Line (45% weight)
    -- ========================================================================
    -- Grid-connected cabins far from lines = end of radial = weak grid
    -- ========================================================================
    0.45 * CASE
        WHEN distance_to_line_m IS NULL THEN 50
        WHEN distance_to_line_m <= 100 THEN 0
        WHEN distance_to_line_m <= 300 THEN
            (distance_to_line_m - 100) / 200.0 * 30
        WHEN distance_to_line_m <= 600 THEN
            30 + (distance_to_line_m - 300) / 300.0 * 40
        WHEN distance_to_line_m <= 1000 THEN
            70 + (distance_to_line_m - 600) / 400.0 * 30
        ELSE 100
    END

    -- ========================================================================
    -- FACTOR 2: Grid Density (35% weight)
    -- ========================================================================
    + 0.35 * CASE
        WHEN grid_density_lines_1km IS NULL OR grid_density_lines_1km = 0 THEN 100
        WHEN grid_density_lines_1km >= 10 THEN 0
        WHEN grid_density_lines_1km >= 6 THEN 20
        WHEN grid_density_lines_1km >= 3 THEN 50
        WHEN grid_density_lines_1km >= 1 THEN 80
        ELSE 100
    END

    -- ========================================================================
    -- FACTOR 3: Voltage Level (12% weight)
    -- ========================================================================
    + 0.12 * CASE
        WHEN voltage_level_kv IS NULL THEN 50
        WHEN voltage_level_kv >= 132 THEN 0
        WHEN voltage_level_kv >= 33 THEN 50
        ELSE 100
    END

    -- ========================================================================
    -- FACTOR 4: Grid Age (8% weight)
    -- ========================================================================
    + 0.08 * CASE
        WHEN grid_age_years IS NULL THEN 50
        WHEN grid_age_years <= 20 THEN 0
        WHEN grid_age_years <= 30 THEN 50
        WHEN grid_age_years <= 40 THEN 75
        ELSE 100
    END
)
WHERE distance_to_line_m <= 1000 AND distance_to_line_m >= 50;

\echo '  ✓ v3.0 scores calculated (KILE removed, transformer data not available)'

-- Show results
SELECT
    COUNT(*) as total_cabins,
    COUNT(weak_grid_score) as scored_v3,
    ROUND(AVG(weak_grid_score)::numeric, 1) as avg_score_v3,
    ROUND(MIN(weak_grid_score)::numeric, 1) as min_score_v3,
    ROUND(MAX(weak_grid_score)::numeric, 1) as max_score_v3
FROM cabins;

\echo ''
\echo '=========================================='
\echo '✓ Weak Grid Scoring v3.0 Complete'
\echo '=========================================='
