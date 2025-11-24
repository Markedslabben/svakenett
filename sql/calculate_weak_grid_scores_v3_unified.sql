-- ============================================================================
-- Calculate Weak Grid Composite Scores v3.0 - UNIFIED BUILDINGS TABLE
-- ============================================================================
-- Purpose: Score ALL buildings (cabins + residential) based on infrastructure
-- Score range: 0-100 (higher = weaker grid = better solar+battery prospect)
-- Reality: Norwegian buildings are often REMOTE - many 2-10km from power lines
-- Author: Klaus
-- Date: 2025-11-24
-- Version: 3.0-UNIFIED
-- ============================================================================

\echo '========================================'
\echo 'Calculating Weak Grid Scores v3.0'
\echo 'UNIFIED TABLE - All Building Types'
\echo '========================================'

-- Reset all scores
UPDATE buildings SET weak_grid_score = NULL;

-- Apply v3.0 scoring - Score ALL buildings within reasonable distance
UPDATE buildings
SET weak_grid_score = (
    -- ========================================================================
    -- FACTOR 1: Distance to Power Line (50% weight)
    -- ========================================================================
    -- Buildings far from infrastructure = weak grid or off-grid
    -- Norwegian reality: Many buildings 2-10km from lines
    -- ========================================================================
    0.50 * CASE
        WHEN distance_to_line_m IS NULL THEN 50
        WHEN distance_to_line_m <= 100 THEN 0          -- Very close = strong grid
        WHEN distance_to_line_m <= 500 THEN 20         -- Close = good grid
        WHEN distance_to_line_m <= 1000 THEN 40        -- Moderate = typical grid-connected
        WHEN distance_to_line_m <= 2000 THEN 60        -- Far = weak grid
        WHEN distance_to_line_m <= 5000 THEN 80        -- Very far = very weak/expensive connection
        ELSE 100                                        -- >5km = likely off-grid
    END

    -- ========================================================================
    -- FACTOR 2: Grid Density (30% weight)
    -- ========================================================================
    + 0.30 * CASE
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
WHERE distance_to_line_m <= 10000;  -- Only score buildings within 10km of infrastructure

\echo '  ✓ v3.0 scores calculated for all building types'

-- Show results by building type
\echo ''
\echo '[Score Distribution by Building Type]'
\echo ''

SELECT
    bygningstype,
    building_type_name,
    building_source,
    COUNT(*) as total_buildings,
    COUNT(weak_grid_score) as scored,
    ROUND(100.0 * COUNT(weak_grid_score) / COUNT(*), 1) as pct_scored,
    ROUND(AVG(weak_grid_score)::numeric, 1) as avg_score,
    ROUND(MIN(weak_grid_score)::numeric, 1) as min_score,
    ROUND(MAX(weak_grid_score)::numeric, 1) as max_score
FROM buildings
GROUP BY bygningstype, building_type_name, building_source
ORDER BY bygningstype;

-- Show results by distance category
\echo ''
\echo '[Score Distribution by Distance to Line]'
\echo ''

SELECT
    CASE
        WHEN distance_to_line_m <= 500 THEN '0-500m (Close)'
        WHEN distance_to_line_m <= 1000 THEN '500-1000m (Moderate)'
        WHEN distance_to_line_m <= 2000 THEN '1-2km (Far)'
        WHEN distance_to_line_m <= 5000 THEN '2-5km (Very Far)'
        WHEN distance_to_line_m <= 10000 THEN '5-10km (Remote)'
        ELSE '>10km (Off-grid)'
    END as distance_category,
    COUNT(*) as building_count,
    ROUND(AVG(weak_grid_score)::numeric, 1) as avg_score,
    ROUND(MIN(weak_grid_score)::numeric, 1) as min_score,
    ROUND(MAX(weak_grid_score)::numeric, 1) as max_score
FROM buildings
WHERE weak_grid_score IS NOT NULL
GROUP BY
    CASE
        WHEN distance_to_line_m <= 500 THEN '0-500m (Close)'
        WHEN distance_to_line_m <= 1000 THEN '500-1000m (Moderate)'
        WHEN distance_to_line_m <= 2000 THEN '1-2km (Far)'
        WHEN distance_to_line_m <= 5000 THEN '2-5km (Very Far)'
        WHEN distance_to_line_m <= 10000 THEN '5-10km (Remote)'
        ELSE '>10km (Off-grid)'
    END
ORDER BY MIN(distance_to_line_m);

-- Overall statistics
\echo ''
\echo '[Overall Statistics]'
\echo ''

SELECT
    COUNT(*) as total_buildings,
    COUNT(weak_grid_score) as scored_buildings,
    ROUND(100.0 * COUNT(weak_grid_score) / COUNT(*), 1) as pct_scored,
    ROUND(AVG(weak_grid_score)::numeric, 1) as avg_score,
    ROUND(MIN(weak_grid_score)::numeric, 1) as min_score,
    ROUND(MAX(weak_grid_score)::numeric, 1) as max_score
FROM buildings;

-- Top prospects by building type
\echo ''
\echo '[Top 10 Highest-Scoring Buildings Per Type]'
\echo ''

WITH ranked_buildings AS (
    SELECT
        bygningstype,
        building_type_name,
        id,
        weak_grid_score,
        distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        postal_code,
        ROW_NUMBER() OVER (PARTITION BY bygningstype ORDER BY weak_grid_score DESC) as rn
    FROM buildings
    WHERE weak_grid_score IS NOT NULL
)
SELECT
    bygningstype,
    building_type_name,
    id,
    ROUND(weak_grid_score::numeric, 1) as score,
    ROUND(distance_to_line_m) as dist_line_m,
    grid_density_lines_1km as density,
    voltage_level_kv as voltage_kv,
    postal_code
FROM ranked_buildings
WHERE rn <= 10
ORDER BY bygningstype, weak_grid_score DESC;

\echo ''
\echo '=========================================='
\echo '✓ Weak Grid Scoring v3.0 UNIFIED Complete'
\echo '=========================================='
