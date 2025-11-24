-- ============================================================================
-- Phase 5: Score Weak Grid Candidates - REVISED WITH VOLTAGE-ADJUSTED THRESHOLDS
-- ============================================================================
-- Purpose: Rank remaining weak grid candidates by composite weakness score
-- Strategy: Voltage-dependent distance thresholds based on electrical engineering
--
-- KEY CHANGES FROM ORIGINAL:
-- - 22-24 kV lines: 15km threshold (was 2km) - realistic for Norwegian distribution
-- - 11-12 kV lines: 8km threshold (was 2km) - adjusted for lower voltage
-- - Unknown voltage: 12km conservative middle ground
--
-- ELECTRICAL ENGINEERING RATIONALE:
-- - 22 kV lines can handle 40-60 km from transformer before stability issues
-- - 11 kV lines can handle 10-20 km from transformer
-- - Residential/cabin loads are LOW (2-5 kW), allowing longer distances
-- - Voltage drop ~2% per 10km for 22kV, ~4% per 10km for 11kV
-- ============================================================================

\echo '========================================='
\echo 'Phase 5: Voltage-Adjusted Weak Grid Scoring'
\echo 'Scoring candidates with realistic distance thresholds'
\echo '========================================='
\echo ''

-- Add scoring column if not exists
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS weak_grid_score_NEW NUMERIC(5,2);

\echo 'Calculating voltage-adjusted weak grid scores...'
\echo ''

-- ============================================================================
-- Composite Weak Grid Score Formula (0-100 scale) - VOLTAGE-ADJUSTED
-- ============================================================================
UPDATE buildings
SET weak_grid_score_NEW = (
    -- ========================================================================
    -- FACTOR 1: Voltage-Adjusted Distance to Transformer (40% weight)
    -- ========================================================================
    0.40 * CASE
        -- 22-24 kV lines (standard Norwegian rural distribution)
        WHEN nearest_line_voltage_kv BETWEEN 22 AND 24 THEN
            CASE
                WHEN nearest_transformer_m IS NULL THEN 50
                WHEN nearest_transformer_m < 15000 THEN 0  -- Normal grid (0-15km)
                WHEN nearest_transformer_m BETWEEN 15000 AND 30000 THEN
                    ((nearest_transformer_m - 15000) / 15000.0) * 50  -- Moderate (15-30km): 0-50pts
                WHEN nearest_transformer_m BETWEEN 30000 AND 50000 THEN
                    50 + ((nearest_transformer_m - 30000) / 20000.0) * 30  -- Weak (30-50km): 50-80pts
                ELSE 80 + LEAST(((nearest_transformer_m - 50000) / 20000.0) * 20, 20)  -- Very weak (>50km): 80-100pts
            END
        
        -- 11-12 kV lines (lower voltage, shorter acceptable distance)
        WHEN nearest_line_voltage_kv BETWEEN 11 AND 12 THEN
            CASE
                WHEN nearest_transformer_m IS NULL THEN 50
                WHEN nearest_transformer_m < 8000 THEN 0  -- Normal grid (0-8km)
                WHEN nearest_transformer_m BETWEEN 8000 AND 15000 THEN
                    ((nearest_transformer_m - 8000) / 7000.0) * 50  -- Moderate (8-15km): 0-50pts
                WHEN nearest_transformer_m BETWEEN 15000 AND 25000 THEN
                    50 + ((nearest_transformer_m - 15000) / 10000.0) * 30  -- Weak (15-25km): 50-80pts
                ELSE 80 + LEAST(((nearest_transformer_m - 25000) / 10000.0) * 20, 20)  -- Very weak (>25km): 80-100pts
            END
        
        -- Unknown voltage (conservative middle ground: 18kV equivalent)
        ELSE
            CASE
                WHEN nearest_transformer_m IS NULL THEN 50
                WHEN nearest_transformer_m < 12000 THEN 0  -- Normal grid (0-12km)
                WHEN nearest_transformer_m BETWEEN 12000 AND 22000 THEN
                    ((nearest_transformer_m - 12000) / 10000.0) * 50  -- Moderate (12-22km): 0-50pts
                WHEN nearest_transformer_m BETWEEN 22000 AND 35000 THEN
                    50 + ((nearest_transformer_m - 22000) / 13000.0) * 30  -- Weak (22-35km): 50-80pts
                ELSE 80 + LEAST(((nearest_transformer_m - 35000) / 15000.0) * 20, 20)  -- Very weak (>35km): 80-100pts
            END
    END

    -- ========================================================================
    -- FACTOR 2: Grid Density (30% weight) - UNCHANGED
    -- ========================================================================
    + 0.30 * CASE
        WHEN grid_density_1km IS NULL OR grid_density_1km = 0 THEN 100
        WHEN grid_density_1km = 1 THEN 90
        WHEN grid_density_1km = 2 THEN 80
        WHEN grid_density_1km BETWEEN 3 AND 5 THEN 50
        WHEN grid_density_1km BETWEEN 6 AND 10 THEN 20
        ELSE 0
    END

    -- ========================================================================
    -- FACTOR 3: Distance to Line (20% weight) - UNCHANGED
    -- ========================================================================
    + 0.20 * CASE
        WHEN distance_to_line_m IS NULL THEN 50
        WHEN distance_to_line_m < 50 THEN 0
        WHEN distance_to_line_m BETWEEN 50 AND 300 THEN 50
        WHEN distance_to_line_m BETWEEN 300 AND 600 THEN 80
        WHEN distance_to_line_m BETWEEN 600 AND 1000 THEN 100
        ELSE 0
    END

    -- ========================================================================
    -- FACTOR 4: Voltage Level (10% weight) - UNCHANGED
    -- ========================================================================
    + 0.10 * CASE
        WHEN nearest_line_voltage_kv IS NULL THEN 50
        WHEN nearest_line_voltage_kv BETWEEN 11 AND 12 THEN 100
        WHEN nearest_line_voltage_kv BETWEEN 22 AND 24 THEN 50
        ELSE 50
    END
)
WHERE grid_status IS NULL;  -- Only score weak grid candidates

\echo '  ✓ Voltage-adjusted weak grid scores calculated'

\echo ''
\echo 'Score Distribution by Tier (NEW SCORES):'

SELECT
    CASE
        WHEN weak_grid_score_NEW >= 80 THEN '⭐ Tier 1: Excellent (80-100)'
        WHEN weak_grid_score_NEW >= 60 THEN '⭐ Tier 2: Good (60-79)'
        WHEN weak_grid_score_NEW >= 40 THEN '   Tier 3: Moderate (40-59)'
        WHEN weak_grid_score_NEW >= 20 THEN '   Tier 4: Low (20-39)'
        ELSE '   Tier 5: Very Low (0-19)'
    END AS tier,
    COUNT(*) AS buildings,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS NUMERIC(5,1)) AS pct,
    CAST(AVG(weak_grid_score_NEW) AS NUMERIC(5,1)) AS avg_score
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW IS NOT NULL
GROUP BY
    CASE
        WHEN weak_grid_score_NEW >= 80 THEN '⭐ Tier 1: Excellent (80-100)'
        WHEN weak_grid_score_NEW >= 60 THEN '⭐ Tier 2: Good (60-79)'
        WHEN weak_grid_score_NEW >= 40 THEN '   Tier 3: Moderate (40-59)'
        WHEN weak_grid_score_NEW >= 20 THEN '   Tier 4: Low (20-39)'
        ELSE '   Tier 5: Very Low (0-19)'
    END
ORDER BY MIN(weak_grid_score_NEW) DESC;

\echo ''
\echo 'Top 20 Weak Grid Prospects (NEW SCORES):'

SELECT
    id,
    CAST(weak_grid_score_NEW AS NUMERIC(5,1)) AS new_score,
    CAST(weak_grid_score AS NUMERIC(5,1)) AS old_score,
    CAST(nearest_transformer_m AS INTEGER) AS transformer_dist_m,
    CAST(distance_to_line_m AS INTEGER) AS line_dist_m,
    COALESCE(grid_density_1km, 0) AS density_1km,
    COALESCE(nearest_line_voltage_kv, 0) AS voltage_kv,
    kommunenavn AS municipality,
    bygningstype AS building_type
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW IS NOT NULL
ORDER BY weak_grid_score_NEW DESC
LIMIT 20;

\echo ''
\echo '========================================='
\echo '✓ Phase 5 Complete - Voltage-Adjusted Weak Grid Scoring'
\echo '========================================='
\echo ''
\echo 'Summary:'

SELECT
    'Total Buildings in Dataset' AS metric,
    COUNT(*)::TEXT AS value
FROM buildings

UNION ALL

SELECT
    'Weak Grid Candidates Scored (NEW)',
    COUNT(*)::TEXT
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW IS NOT NULL

UNION ALL

SELECT
    'Tier 1: Excellent (80-100)',
    COUNT(*)::TEXT
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW >= 80

UNION ALL

SELECT
    'Tier 2: Good (60-79)',
    COUNT(*)::TEXT
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW >= 60 AND weak_grid_score_NEW < 80

UNION ALL

SELECT
    'Tier 3: Moderate (40-59)',
    COUNT(*)::TEXT
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW >= 40 AND weak_grid_score_NEW < 60

UNION ALL

SELECT
    'HIGH-VALUE TARGETS (Tiers 1+2)',
    COUNT(*)::TEXT
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW >= 60;

\echo ''
\echo 'Scoring Method: Voltage-adjusted transformer distance (22kV: 15km, 11kV: 8km thresholds)'
\echo ''

