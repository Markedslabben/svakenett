-- ============================================================================
-- Validation Queries: Compare Old vs. New Weak Grid Scores
-- ============================================================================
-- Purpose: Analyze impact of voltage-adjusted distance thresholds
-- Compare: Original 2km threshold vs. New voltage-dependent thresholds
-- ============================================================================

\echo '========================================='
\echo 'Weak Grid Score Validation: Old vs. New'
\echo 'Comparing conservative 2km vs. realistic voltage-adjusted thresholds'
\echo '========================================='
\echo ''

-- ============================================================================
-- COMPARISON 1: Overall Score Distribution Changes
-- ============================================================================

\echo 'COMPARISON 1: Score Distribution Changes'
\echo '========================================='
\echo ''

SELECT
    score_range,
    old_count,
    new_count,
    (new_count - old_count) AS change,
    CAST(CASE
        WHEN old_count > 0 THEN ((new_count - old_count)::NUMERIC / old_count * 100)
        ELSE NULL
    END AS NUMERIC(6,1)) AS pct_change
FROM (
    SELECT
        '80-100 (Tier 1)' AS score_range,
        COUNT(*) FILTER (WHERE weak_grid_score >= 80) AS old_count,
        COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 80) AS new_count
    FROM buildings
    WHERE grid_status IS NULL

    UNION ALL

    SELECT
        '60-79 (Tier 2)',
        COUNT(*) FILTER (WHERE weak_grid_score >= 60 AND weak_grid_score < 80),
        COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 60 AND weak_grid_score_NEW < 80)
    FROM buildings
    WHERE grid_status IS NULL

    UNION ALL

    SELECT
        '40-59 (Tier 3)',
        COUNT(*) FILTER (WHERE weak_grid_score >= 40 AND weak_grid_score < 60),
        COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 40 AND weak_grid_score_NEW < 60)
    FROM buildings
    WHERE grid_status IS NULL

    UNION ALL

    SELECT
        '0-39 (Tier 4+5)',
        COUNT(*) FILTER (WHERE weak_grid_score < 40),
        COUNT(*) FILTER (WHERE weak_grid_score_NEW < 40)
    FROM buildings
    WHERE grid_status IS NULL
) subq
ORDER BY score_range DESC;

-- ============================================================================
-- COMPARISON 2: Tier Migrations (which buildings moved up/down?)
-- ============================================================================

\echo ''
\echo 'COMPARISON 2: Tier Migration Analysis'
\echo '========================================='
\echo ''

SELECT
    old_tier,
    new_tier,
    COUNT(*) AS buildings,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS NUMERIC(5,1)) AS pct
FROM (
    SELECT
        CASE
            WHEN weak_grid_score >= 80 THEN 'Tier 1 (80-100)'
            WHEN weak_grid_score >= 60 THEN 'Tier 2 (60-79)'
            WHEN weak_grid_score >= 40 THEN 'Tier 3 (40-59)'
            ELSE 'Tier 4+5 (<40)'
        END AS old_tier,
        CASE
            WHEN weak_grid_score_NEW >= 80 THEN 'Tier 1 (80-100)'
            WHEN weak_grid_score_NEW >= 60 THEN 'Tier 2 (60-79)'
            WHEN weak_grid_score_NEW >= 40 THEN 'Tier 3 (40-59)'
            ELSE 'Tier 4+5 (<40)'
        END AS new_tier
    FROM buildings
    WHERE grid_status IS NULL
      AND weak_grid_score IS NOT NULL
      AND weak_grid_score_NEW IS NOT NULL
) tier_comparison
GROUP BY old_tier, new_tier
ORDER BY
    CASE old_tier
        WHEN 'Tier 1 (80-100)' THEN 1
        WHEN 'Tier 2 (60-79)' THEN 2
        WHEN 'Tier 3 (40-59)' THEN 3
        ELSE 4
    END,
    CASE new_tier
        WHEN 'Tier 1 (80-100)' THEN 1
        WHEN 'Tier 2 (60-79)' THEN 2
        WHEN 'Tier 3 (40-59)' THEN 3
        ELSE 4
    END;

-- ============================================================================
-- COMPARISON 3: Impact by Voltage Level
-- ============================================================================

\echo ''
\echo 'COMPARISON 3: Score Changes by Voltage Level'
\echo '========================================='
\echo ''

SELECT
    voltage_category,
    COUNT(*) AS buildings,
    CAST(AVG(weak_grid_score) AS NUMERIC(5,1)) AS avg_old_score,
    CAST(AVG(weak_grid_score_NEW) AS NUMERIC(5,1)) AS avg_new_score,
    CAST(AVG(weak_grid_score_NEW - weak_grid_score) AS NUMERIC(5,1)) AS avg_change,
    COUNT(*) FILTER (WHERE weak_grid_score_NEW > weak_grid_score) AS increased,
    COUNT(*) FILTER (WHERE weak_grid_score_NEW < weak_grid_score) AS decreased
FROM (
    SELECT
        CASE
            WHEN nearest_line_voltage_kv BETWEEN 22 AND 24 THEN '22-24 kV'
            WHEN nearest_line_voltage_kv BETWEEN 11 AND 12 THEN '11-12 kV'
            WHEN nearest_line_voltage_kv IS NULL THEN 'Unknown'
            ELSE 'Other'
        END AS voltage_category,
        weak_grid_score,
        weak_grid_score_NEW
    FROM buildings
    WHERE grid_status IS NULL
      AND weak_grid_score IS NOT NULL
      AND weak_grid_score_NEW IS NOT NULL
) voltage_analysis
GROUP BY voltage_category
ORDER BY voltage_category;

-- ============================================================================
-- COMPARISON 4: Impact by Distance from Transformer
-- ============================================================================

\echo ''
\echo 'COMPARISON 4: Score Changes by Distance from Transformer'
\echo '========================================='
\echo ''

SELECT
    distance_band,
    COUNT(*) AS buildings,
    CAST(AVG(weak_grid_score) AS NUMERIC(5,1)) AS avg_old_score,
    CAST(AVG(weak_grid_score_NEW) AS NUMERIC(5,1)) AS avg_new_score,
    CAST(AVG(weak_grid_score_NEW - weak_grid_score) AS NUMERIC(5,1)) AS avg_change
FROM (
    SELECT
        CASE
            WHEN nearest_transformer_m < 5000 THEN '0-5 km'
            WHEN nearest_transformer_m < 15000 THEN '5-15 km'
            WHEN nearest_transformer_m < 30000 THEN '15-30 km'
            WHEN nearest_transformer_m < 50000 THEN '30-50 km'
            ELSE '>50 km'
        END AS distance_band,
        weak_grid_score,
        weak_grid_score_NEW
    FROM buildings
    WHERE grid_status IS NULL
      AND weak_grid_score IS NOT NULL
      AND weak_grid_score_NEW IS NOT NULL
) distance_analysis
GROUP BY distance_band
ORDER BY
    CASE distance_band
        WHEN '0-5 km' THEN 1
        WHEN '5-15 km' THEN 2
        WHEN '15-30 km' THEN 3
        WHEN '30-50 km' THEN 4
        ELSE 5
    END;

-- ============================================================================
-- COMPARISON 5: Top Movers (biggest score increases)
-- ============================================================================

\echo ''
\echo 'COMPARISON 5: Top 20 Buildings with Largest Score Increases'
\echo '========================================='
\echo ''

SELECT
    id,
    CAST(weak_grid_score AS NUMERIC(5,1)) AS old_score,
    CAST(weak_grid_score_NEW AS NUMERIC(5,1)) AS new_score,
    CAST(weak_grid_score_NEW - weak_grid_score AS NUMERIC(5,1)) AS score_increase,
    CAST(nearest_transformer_m / 1000.0 AS NUMERIC(5,1)) AS transformer_km,
    CAST(distance_to_line_m AS INTEGER) AS line_m,
    nearest_line_voltage_kv AS voltage_kv,
    kommunenavn AS municipality
FROM buildings
WHERE grid_status IS NULL
  AND weak_grid_score IS NOT NULL
  AND weak_grid_score_NEW IS NOT NULL
ORDER BY (weak_grid_score_NEW - weak_grid_score) DESC
LIMIT 20;

-- ============================================================================
-- COMPARISON 6: High-Value Targets Impact
-- ============================================================================

\echo ''
\echo 'COMPARISON 6: High-Value Targets (Tier 1+2) Comparison'
\echo '========================================='
\echo ''

SELECT
    'Old Methodology (2km threshold)' AS methodology,
    COUNT(*) AS tier1_plus_tier2_count,
    COUNT(*) FILTER (WHERE weak_grid_score >= 80) AS tier1_count,
    COUNT(*) FILTER (WHERE weak_grid_score >= 60 AND weak_grid_score < 80) AS tier2_count
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score >= 60

UNION ALL

SELECT
    'New Methodology (voltage-adjusted)',
    COUNT(*),
    COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 80),
    COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 60 AND weak_grid_score_NEW < 80)
FROM buildings
WHERE grid_status IS NULL AND weak_grid_score_NEW >= 60;

-- ============================================================================
-- COMPARISON 7: Geographic Distribution Changes (Top Municipalities)
-- ============================================================================

\echo ''
\echo 'COMPARISON 7: Top 10 Municipalities - High-Value Target Changes'
\echo '========================================='
\echo ''

SELECT
    kommunenavn,
    COUNT(*) FILTER (WHERE weak_grid_score >= 60) AS old_tier1_plus_2,
    COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 60) AS new_tier1_plus_2,
    (COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 60) -
     COUNT(*) FILTER (WHERE weak_grid_score >= 60)) AS change
FROM buildings
WHERE grid_status IS NULL
GROUP BY kommunenavn
HAVING COUNT(*) FILTER (WHERE weak_grid_score >= 60) > 0
    OR COUNT(*) FILTER (WHERE weak_grid_score_NEW >= 60) > 0
ORDER BY new_tier1_plus_2 DESC
LIMIT 10;

\echo ''
\echo '========================================='
\echo 'Validation Analysis Complete'
\echo '========================================='
\echo ''
