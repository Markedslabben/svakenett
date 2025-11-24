#!/bin/bash
# Apply weighted scoring formula to calculate weak_grid_score for all cabins
# Implements the algorithm defined in docs/SCORING_ALGORITHM_DESIGN.md

set -e  # Exit on error

echo "=========================================="
echo "Applying Weak Grid Scoring Algorithm"
echo "=========================================="

DB_CONTAINER="svakenett-postgis"
DB_NAME="svakenett"
DB_USER="postgres"

# Check database connection
if ! docker ps | grep -q $DB_CONTAINER; then
    echo "✗ Error: PostgreSQL container not running"
    exit 1
fi

# ===========================================================================
# STEP 1: Calculate Individual Metric Scores (normalized 0-100)
# ===========================================================================
echo ""
echo "1. Normalizing individual metrics to 0-100 scale..."

# Score 1: Distance to Line (40% weight)
echo "   - Distance score (0-100m=0pts, 100-500m=0-50pts, 500-2000m=50-90pts, 2000m+=100pts)"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET score_distance = CASE
    WHEN distance_to_line_m IS NULL THEN NULL
    WHEN distance_to_line_m <= 100 THEN 0
    WHEN distance_to_line_m <= 500 THEN
        ((distance_to_line_m - 100) / 400.0) * 50
    WHEN distance_to_line_m <= 2000 THEN
        50 + ((distance_to_line_m - 500) / 1500.0) * 40
    ELSE 100
END;
SQL

# Score 2: Grid Density (25% weight)
echo "   - Density score (0 lines=100pts, 1-2=80pts, 3-5=50pts, 6-10=20pts, 10+=0pts)"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET score_density = CASE
    WHEN grid_density_lines_1km IS NULL THEN NULL
    WHEN grid_density_lines_1km >= 10 THEN 0
    WHEN grid_density_lines_1km >= 6 THEN 20
    WHEN grid_density_lines_1km >= 3 THEN 50
    WHEN grid_density_lines_1km >= 1 THEN 80
    ELSE 100
END;
SQL

# Score 3: KILE Costs (15% weight)
echo "   - KILE score (0-500=0pts, 500-1500=0-50pts, 1500-3000=50-80pts, 3000+=100pts)"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins c
SET score_kile = CASE
    WHEN gc.kile_cost_nok IS NULL THEN NULL
    WHEN gc.kile_cost_nok <= 500 THEN 0
    WHEN gc.kile_cost_nok <= 1500 THEN
        ((gc.kile_cost_nok - 500) / 1000.0) * 50
    WHEN gc.kile_cost_nok <= 3000 THEN
        50 + ((gc.kile_cost_nok - 1500) / 1500.0) * 30
    ELSE 100
END
FROM grid_companies gc
WHERE c.grid_company_code = gc.company_code;
SQL

# Score 4: Voltage Level (10% weight)
echo "   - Voltage score (22kV=100pts, 33-66kV=50pts, 132kV+=0pts)"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET score_voltage = CASE
    WHEN voltage_level_kv IS NULL THEN NULL
    WHEN voltage_level_kv >= 132 THEN 0
    WHEN voltage_level_kv >= 33 THEN 50
    ELSE 100
END;
SQL

# Score 5: Grid Age (10% weight)
echo "   - Age score (0-10yrs=0pts, 10-20=25pts, 20-30=50pts, 30-40=75pts, 40+=100pts)"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET score_age = CASE
    WHEN grid_age_years IS NULL THEN NULL
    WHEN grid_age_years <= 10 THEN 0
    WHEN grid_age_years <= 20 THEN 25
    WHEN grid_age_years <= 30 THEN 50
    WHEN grid_age_years <= 40 THEN 75
    ELSE 100
END;
SQL

echo "   ✓ All metric scores normalized"

# ===========================================================================
# STEP 2: Calculate Weighted Composite Score
# ===========================================================================
echo ""
echo "2. Calculating weighted composite score..."
echo "   Formula: 40% distance + 25% density + 15% KILE + 10% voltage + 10% age"

docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET weak_grid_score = ROUND(
    (0.40 * COALESCE(score_distance, 0)) +
    (0.25 * COALESCE(score_density, 0)) +
    (0.15 * COALESCE(score_kile, 0)) +
    (0.10 * COALESCE(score_voltage, 0)) +
    (0.10 * COALESCE(score_age, 0))
, 2)
WHERE score_distance IS NOT NULL;  -- Only score cabins with distance data
SQL

echo "   ✓ Composite scores calculated"

# ===========================================================================
# STEP 3: Assign Score Categories
# ===========================================================================
echo ""
echo "3. Assigning score categories..."

docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
UPDATE cabins
SET score_category = CASE
    WHEN weak_grid_score >= 90 THEN 'Excellent Prospect (90-100)'
    WHEN weak_grid_score >= 70 THEN 'Good Prospect (70-89)'
    WHEN weak_grid_score >= 50 THEN 'Moderate Prospect (50-69)'
    WHEN weak_grid_score >= 0 THEN 'Poor Prospect (0-49)'
    ELSE NULL
END,
scoring_updated_at = NOW()
WHERE weak_grid_score IS NOT NULL;
SQL

echo "   ✓ Categories assigned"

# ===========================================================================
# STEP 4: Verification and Statistics
# ===========================================================================
echo ""
echo "=========================================="
echo "Scoring Results"
echo "=========================================="

echo ""
echo "4. Score Distribution by Category:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    score_category,
    COUNT(*) as cabin_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage,
    ROUND(MIN(weak_grid_score), 1) as min_score,
    ROUND(AVG(weak_grid_score), 1) as avg_score,
    ROUND(MAX(weak_grid_score), 1) as max_score
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY score_category
ORDER BY MIN(weak_grid_score) DESC;
SQL

echo ""
echo "5. Top 20 Highest Scoring Cabins (Weakest Grids):"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    c.id,
    c.postal_code,
    gc.company_name as grid_company,
    ROUND(c.distance_to_line_m, 0) as dist_m,
    c.grid_density_lines_1km as density,
    ROUND(c.grid_age_years, 1) as age_yrs,
    c.voltage_level_kv as voltage,
    gc.kile_cost_nok as kile,
    ROUND(c.weak_grid_score, 1) as score,
    ST_X(c.geometry) as lon,
    ST_Y(c.geometry) as lat
FROM cabins c
LEFT JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE c.weak_grid_score IS NOT NULL
ORDER BY c.weak_grid_score DESC, c.distance_to_line_m DESC
LIMIT 20;
SQL

echo ""
echo "6. Metric Correlation Analysis:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    'Distance vs Score' as correlation,
    ROUND(CORR(distance_to_line_m, weak_grid_score)::numeric, 3) as correlation_coef
FROM cabins
WHERE weak_grid_score IS NOT NULL AND distance_to_line_m IS NOT NULL

UNION ALL

SELECT
    'Density vs Score' as correlation,
    ROUND(CORR(grid_density_lines_1km, weak_grid_score)::numeric, 3) as correlation_coef
FROM cabins
WHERE weak_grid_score IS NOT NULL AND grid_density_lines_1km IS NOT NULL

UNION ALL

SELECT
    'Age vs Score' as correlation,
    ROUND(CORR(grid_age_years, weak_grid_score)::numeric, 3) as correlation_coef
FROM cabins
WHERE weak_grid_score IS NOT NULL AND grid_age_years IS NOT NULL

UNION ALL

SELECT
    'KILE vs Score' as correlation,
    ROUND(CORR(gc.kile_cost_nok, c.weak_grid_score)::numeric, 3) as correlation_coef
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE c.weak_grid_score IS NOT NULL;
SQL

echo ""
echo "7. Geographic Distribution of High-Value Prospects:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    LEFT(postal_code, 2) as postal_prefix,
    COUNT(*) FILTER (WHERE weak_grid_score >= 90) as excellent_prospects,
    COUNT(*) FILTER (WHERE weak_grid_score >= 70) as good_or_better,
    COUNT(*) as total_cabins,
    ROUND(AVG(weak_grid_score), 1) as avg_score
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY LEFT(postal_code, 2)
HAVING COUNT(*) FILTER (WHERE weak_grid_score >= 70) > 0
ORDER BY COUNT(*) FILTER (WHERE weak_grid_score >= 90) DESC
LIMIT 10;
SQL

echo ""
echo "8. Grid Company Comparison - Weak Grid Performance:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    gc.company_name,
    gc.kile_cost_nok,
    COUNT(c.id) as total_cabins,
    COUNT(*) FILTER (WHERE c.weak_grid_score >= 90) as excellent_prospects,
    COUNT(*) FILTER (WHERE c.weak_grid_score >= 70) as good_or_better,
    ROUND(AVG(c.weak_grid_score), 1) as avg_score,
    ROUND(AVG(c.distance_to_line_m), 0) as avg_distance_m
FROM grid_companies gc
JOIN cabins c ON gc.company_code = c.grid_company_code
WHERE c.weak_grid_score IS NOT NULL
GROUP BY gc.company_name, gc.kile_cost_nok
HAVING COUNT(c.id) >= 10  -- Only companies with 10+ cabins
ORDER BY AVG(c.weak_grid_score) DESC
LIMIT 15;
SQL

# ===========================================================================
# STEP 5: Refresh Materialized Views
# ===========================================================================
echo ""
echo "9. Refreshing materialized views..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT refresh_grid_analytics();
SQL

echo "   ✓ Materialized views refreshed"

# ===========================================================================
# STEP 6: Export High-Value Prospects
# ===========================================================================
echo ""
echo "10. Exporting high-value prospects to CSV..."

docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
\copy (
    SELECT
        c.id,
        c.postal_code,
        gc.company_name as grid_company,
        gc.kile_cost_nok,
        c.distance_to_line_m,
        c.grid_density_lines_1km,
        c.grid_age_years,
        c.voltage_level_kv,
        c.weak_grid_score,
        c.score_category,
        ST_X(c.geometry) as longitude,
        ST_Y(c.geometry) as latitude
    FROM cabins c
    LEFT JOIN grid_companies gc ON c.grid_company_code = gc.company_code
    WHERE c.weak_grid_score >= 70
    ORDER BY c.weak_grid_score DESC
) TO '/tmp/high_value_prospects.csv' WITH CSV HEADER;
SQL

# Copy from container to host
docker cp $DB_CONTAINER:/tmp/high_value_prospects.csv data/high_value_prospects.csv

prospect_count=$(wc -l < data/high_value_prospects.csv)
prospect_count=$((prospect_count - 1))  # Subtract header row

echo "   ✓ Exported $prospect_count prospects to data/high_value_prospects.csv"

echo ""
echo "=========================================="
echo "[OK] Scoring Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - All cabins scored with weighted algorithm"
echo "  - Score range: 0-100 (higher = weaker grid = better prospect)"
echo "  - Categories: Excellent (90-100), Good (70-89), Moderate (50-69), Poor (0-49)"
echo "  - High-value prospects exported to data/high_value_prospects.csv"
echo ""
echo "Next steps:"
echo "  - Review top prospects in data/high_value_prospects.csv"
echo "  - Visualize results in QGIS or similar GIS tool"
echo "  - Cross-reference with business constraints (road access, etc.)"
