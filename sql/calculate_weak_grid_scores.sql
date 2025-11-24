-- ============================================================================
-- Calculate Weak Grid Composite Scores (REVISED v3.0)
-- ============================================================================
-- Purpose: Apply multi-factor scoring algorithm to rank cabins by weak grid likelihood
-- Score range: 0-100 (higher = weaker grid = better hybrid solar+battery prospect)
-- Dependencies: cabins table with grid distance/density metrics populated
-- Author: Klaus
-- Date: 2025-11-24
-- Version: 3.0 - REMOVED KILE (no geographic differentiation in single-company regions)
-- ============================================================================

\echo '========================================'
\echo 'Calculating Weak Grid Composite Scores'
\echo 'Version 3.0 - KILE Removed'
\echo '========================================'

-- ============================================================================
-- KEY CHANGES FROM v2.0
-- ============================================================================
-- ❌ REMOVED: KILE scoring (20%) - single grid company in Agder = no differentiation
-- ✅ INCREASED: Distance-to-transformer (30% → 40%) - most important weak grid indicator
-- ✅ INCREASED: Grid density (30% → 35%) - primary infrastructure indicator
-- ✅ KEPT: Voltage (10%) and Age (10%) - secondary indicators
-- ============================================================================

\echo ''
\echo '[IMPORTANT] Scoring Logic Changes from v2.0:'
\echo '  - KILE REMOVED: Single grid company (Glitre Nett) = no geographic variation'
\echo '  - Distance-to-transformer: 40% (increased from 30%)'
\echo '  - Grid density: 35% (increased from 30%)'
\echo '  - Voltage level: 15% (increased from 10%)'
\echo '  - Grid age: 10% (unchanged)'
\echo ''

-- ============================================================================
-- REVISED SCORING ALGORITHM v3.0
-- ============================================================================
-- FILTER: Only grid-connected cabins (distance_to_line <= 1000m)
--
-- 40% - Distance to Transformer (far from power source = weak grid)
-- 35% - Grid Density (sparse infrastructure = weak grid)
-- 15% - Voltage Level (22kV distribution = weaker than regional)
-- 10% - Grid Age (old infrastructure = unreliable)
-- ============================================================================

\echo ''
\echo '[1/3] Applying revised composite scoring algorithm...'

-- Reset all scores first
UPDATE cabins SET weak_grid_score = NULL;

-- Apply scoring ONLY to grid-connected cabins
UPDATE cabins
SET weak_grid_score = (
    -- ========================================================================
    -- FACTOR 1: Distance to Transformer (40% weight) - INCREASED from 30%
    -- ========================================================================
    -- Measures how far the cabin is from the power source
    -- Long radials = voltage drop, power quality issues, outage risk
    --
    -- <=2km:    Score 0    (close to transformer = strong grid)
    -- 2-5km:    Score 0-40 (moderate distance)
    -- 5-10km:   Score 40-70 (long radial = weak grid)
    -- >10km:    Score 100  (very long radial = very weak)
    -- ========================================================================
    0.40 * CASE
        WHEN distance_to_transformer_m IS NULL THEN 50  -- Unknown distance
        WHEN distance_to_transformer_m <= 2000 THEN 0
        WHEN distance_to_transformer_m <= 5000 THEN
            (distance_to_transformer_m - 2000) / 3000.0 * 40
        WHEN distance_to_transformer_m <= 10000 THEN
            40 + (distance_to_transformer_m - 5000) / 5000.0 * 30
        ELSE 100
    END

    -- ========================================================================
    -- FACTOR 2: Grid Density (35% weight) - INCREASED from 30%
    -- ========================================================================
    -- Sparse grid infrastructure = weak grid, isolated, vulnerable
    -- Primary indicator of grid weakness in rural areas
    --
    -- >=10 lines: Score 0   (dense/strong grid)
    -- 6-10 lines: Score 20  (moderate density)
    -- 3-6 lines:  Score 50  (sparse grid)
    -- 1-3 lines:  Score 80  (very sparse = weak)
    -- 0 lines:    Score 100 (isolated - should not happen with connectivity filter)
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
    -- FACTOR 3: Voltage Level (15% weight) - INCREASED from 10%
    -- ========================================================================
    -- Lower voltage = weaker grid, more voltage drop, less capacity
    --
    -- >=132 kV: Score 0   (transmission/regional = strong)
    -- 33-132 kV: Score 50 (regional distribution)
    -- 22-24 kV:  Score 100 (weak distribution grid)
    -- ========================================================================
    + 0.15 * CASE
        WHEN voltage_level_kv IS NULL THEN 50
        WHEN voltage_level_kv >= 132 THEN 0
        WHEN voltage_level_kv >= 33 THEN 50
        ELSE 100  -- 22-24 kV distribution
    END

    -- ========================================================================
    -- FACTOR 4: Grid Age (10% weight) - UNCHANGED
    -- ========================================================================
    -- Old infrastructure = higher failure risk, outdated technology
    --
    -- <=20 years: Score 0   (new/modern infrastructure)
    -- 20-30 years: Score 50 (aging)
    -- 30-40 years: Score 75 (old)
    -- >40 years:   Score 100 (very old/unreliable)
    -- ========================================================================
    + 0.10 * CASE
        WHEN grid_age_years IS NULL THEN 50
        WHEN grid_age_years <= 20 THEN 0
        WHEN grid_age_years <= 30 THEN 50
        WHEN grid_age_years <= 40 THEN 75
        ELSE 100
    END
)
WHERE
  -- ========================================================================
  -- CONNECTIVITY FILTER: Only score grid-connected cabins
  -- ========================================================================
  -- Distance ≤1000m = likely grid-connected (typical connection distance)
  -- Distance ≥50m = not directly adjacent to line (avoid substations/industry)
  -- ========================================================================
  cabins.distance_to_line_m <= 1000
  AND cabins.distance_to_line_m >= 50;

\echo '  ✓ Weak grid scores calculated (grid-connected cabins only)'

-- Show how many cabins were scored vs excluded
\echo ''
\echo '[Connectivity Filter Results]'
\echo ''

SELECT
    'Total Cabins' as category,
    COUNT(*) as count,
    '100.0%' as percentage
FROM cabins

UNION ALL

SELECT
    'Grid-Connected (scored)',
    COUNT(*),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM cabins), 1)::text || '%'
FROM cabins
WHERE weak_grid_score IS NOT NULL

UNION ALL

SELECT
    'Likely Off-Grid (not scored)',
    COUNT(*),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM cabins), 1)::text || '%'
FROM cabins
WHERE distance_to_line_m > 1000

UNION ALL

SELECT
    'Too Close to Line (not scored)',
    COUNT(*),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM cabins), 1)::text || '%'
FROM cabins
WHERE distance_to_line_m < 50;

-- ============================================================================
-- STEP 2: Validation & Score Distribution Analysis
-- ============================================================================

\echo ''
\echo '[2/3] Score Distribution Analysis'
\echo ''

-- Overall statistics
SELECT
    'Weak Grid Scores' as metric,
    COUNT(*) as cabins,
    ROUND(MIN(weak_grid_score), 1) as min_score,
    ROUND(AVG(weak_grid_score), 1) as avg_score,
    ROUND(MAX(weak_grid_score), 1) as max_score,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY weak_grid_score), 1) as median_score
FROM cabins
WHERE weak_grid_score IS NOT NULL;

-- Distribution by category
\echo ''
\echo '[Score Distribution by Category]'
\echo ''

SELECT
    CASE
        WHEN weak_grid_score >= 90 THEN '🔴 Excellent Prospects (90-100)'
        WHEN weak_grid_score >= 70 THEN '🟡 Good Prospects (70-89)'
        WHEN weak_grid_score >= 50 THEN '🟢 Moderate Prospects (50-69)'
        ELSE '⚪ Poor Prospects (0-49)'
    END as category,
    COUNT(*) as cabin_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage,
    ROUND(AVG(distance_to_line_m), 0) as avg_distance_to_line_m,
    ROUND(AVG(nearest_transformer_m), 0) as avg_distance_to_transformer_m,
    ROUND(AVG(grid_density_1km), 1) as avg_density,
    ROUND(AVG(nearest_line_age_years), 1) as avg_age_years
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY
    CASE
        WHEN weak_grid_score >= 90 THEN '🔴 Excellent Prospects (90-100)'
        WHEN weak_grid_score >= 70 THEN '🟡 Good Prospects (70-89)'
        WHEN weak_grid_score >= 50 THEN '🟢 Moderate Prospects (50-69)'
        ELSE '⚪ Poor Prospects (0-49)'
    END
ORDER BY MIN(weak_grid_score) DESC;

-- Top scoring cabins (highest weak grid scores)
\echo ''
\echo '[Top 10 Highest-Scoring Cabins]'
\echo ''

SELECT
    id,
    ROUND(weak_grid_score, 1) as score,
    ROUND(distance_to_line_m, 0) as dist_line_m,
    ROUND(nearest_transformer_m, 0) as dist_transformer_m,
    grid_density_1km as density,
    nearest_line_voltage_kv as voltage_kv,
    nearest_line_age_years as age_yrs,
    municipality
FROM cabins
WHERE weak_grid_score IS NOT NULL
ORDER BY weak_grid_score DESC
LIMIT 10;

-- Distribution by transformer distance (key new metric)
\echo ''
\echo '[Distribution by Distance to Transformer]'
\echo ''

SELECT
    CASE
        WHEN nearest_transformer_m <= 2000 THEN '0-2km (Close)'
        WHEN nearest_transformer_m <= 5000 THEN '2-5km (Moderate)'
        WHEN nearest_transformer_m <= 10000 THEN '5-10km (Far - Weak Grid)'
        ELSE '>10km (Very Far - Very Weak)'
    END as distance_category,
    COUNT(*) as cabins,
    ROUND(AVG(weak_grid_score), 1) as avg_score,
    ROUND(AVG(grid_density_1km), 1) as avg_density
FROM cabins
WHERE weak_grid_score IS NOT NULL
  AND nearest_transformer_m IS NOT NULL
GROUP BY
    CASE
        WHEN nearest_transformer_m <= 2000 THEN '0-2km (Close)'
        WHEN nearest_transformer_m <= 5000 THEN '2-5km (Moderate)'
        WHEN nearest_transformer_m <= 10000 THEN '5-10km (Far - Weak Grid)'
        ELSE '>10km (Very Far - Very Weak)'
    END
ORDER BY MIN(nearest_transformer_m);

-- ============================================================================
-- STEP 3: Generate Top 500 Leads Export View
-- ============================================================================

\echo ''
\echo '[3/3] Creating Top 500 Leads View'

DROP VIEW IF EXISTS top_500_weak_grid_leads;

CREATE VIEW top_500_weak_grid_leads AS
SELECT
    id,
    weak_grid_score,
    distance_to_line_m,
    nearest_transformer_m,
    grid_density_1km,
    nearest_line_voltage_kv,
    nearest_line_age_years,
    municipality,
    postal_code,
    ST_Y(geometry) as latitude,
    ST_X(geometry) as longitude,

    -- Add ranking within each postal code (for GDPR-compliant aggregation)
    ROW_NUMBER() OVER (
        PARTITION BY postal_code
        ORDER BY weak_grid_score DESC
    ) as postal_rank,

    -- Grid company reference (informational only - not used in scoring)
    grid_company_code

FROM cabins
WHERE weak_grid_score >= 70  -- Good to Excellent prospects only
  AND weak_grid_score IS NOT NULL
ORDER BY weak_grid_score DESC
LIMIT 500;

\echo '  ✓ View created: top_500_weak_grid_leads'

-- Sample top leads
\echo ''
\echo '[Sample Top 5 Leads]'
\echo ''

SELECT
    id,
    ROUND(weak_grid_score, 1) as score,
    municipality,
    postal_code,
    ROUND(distance_to_line_m, 0) as dist_line_m,
    ROUND(nearest_transformer_m, 0) as dist_transf_m,
    grid_density_1km as density
FROM top_500_weak_grid_leads
LIMIT 5;

-- ============================================================================
-- ADDITIONAL: Off-Grid Cabins View (for future offgrid product)
-- ============================================================================

\echo ''
\echo '[Bonus] Creating Off-Grid Cabins View'

DROP VIEW IF EXISTS potential_offgrid_cabins;

CREATE VIEW potential_offgrid_cabins AS
SELECT
    id,
    distance_to_line_m,
    nearest_transformer_m,
    municipality,
    postal_code,
    ST_Y(geometry) as latitude,
    ST_X(geometry) as longitude,

    -- Simple off-grid score (higher distance = better prospect)
    CASE
        WHEN distance_to_line_m > 5000 THEN 100
        WHEN distance_to_line_m > 2000 THEN 70
        WHEN distance_to_line_m > 1000 THEN 40
        ELSE 0
    END as offgrid_score

FROM cabins
WHERE distance_to_line_m > 1000  -- Beyond typical grid connection distance
ORDER BY distance_to_line_m DESC;

\echo '  ✓ View created: potential_offgrid_cabins (for future offgrid product line)'

-- ============================================================================
-- SUCCESS SUMMARY
-- ============================================================================

\echo ''
\echo '========================================'
\echo '✓ Weak Grid Scoring Complete (v2.0)'
\echo '========================================'
\echo ''

-- Final summary
SELECT
    'Total Cabins' as metric,
    COUNT(*)::text as value
FROM cabins

UNION ALL

SELECT
    'Grid-Connected & Scored',
    COUNT(*)::text
FROM cabins
WHERE weak_grid_score IS NOT NULL

UNION ALL

SELECT
    'High-Priority Prospects (Score ≥90)',
    COUNT(*)::text
FROM cabins
WHERE weak_grid_score >= 90

UNION ALL

SELECT
    'Good Prospects (Score ≥70)',
    COUNT(*)::text
FROM cabins
WHERE weak_grid_score >= 70

UNION ALL

SELECT
    'Average Weak Grid Score',
    ROUND(AVG(weak_grid_score), 1)::text
FROM cabins
WHERE weak_grid_score IS NOT NULL

UNION ALL

SELECT
    'Potential Off-Grid Cabins (>1km)',
    COUNT(*)::text
FROM cabins
WHERE distance_to_line_m > 1000;

\echo ''
\echo 'Key Changes in v3.0:'
\echo '  ✓ REMOVED: KILE scoring (20%) - no geographic differentiation with single grid company'
\echo '  ✓ Distance-to-transformer: 40% weight (increased from 30%)'
\echo '  ✓ Grid density: 35% weight (increased from 30%)'
\echo '  ✓ Voltage level: 15% weight (increased from 10%)'
\echo '  ✓ Grid age: 10% weight (unchanged)'
\echo '  ✓ 100% infrastructure-based scoring with geographic variation'
\echo ''
\echo 'Next steps:'
\echo '  1. Export top leads: COPY (SELECT * FROM top_500_weak_grid_leads) TO ''/tmp/top_500_leads.csv'' CSV HEADER;'
\echo '  2. Visualize in QGIS: Load cabins layer, symbolize by weak_grid_score'
\echo '  3. Validate scores against known weak grid areas (when dataset available)'
\echo '  4. Create postal code aggregates for GDPR compliance'
\echo ''
