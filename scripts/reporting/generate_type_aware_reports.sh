#!/bin/bash
# Generate type-aware weak grid analysis reports
# Apply different score thresholds per building type per ChatGPT recommendation
#
# Thresholds:
#   - Cabins (161): score >= 70 (intermittent use, higher outage tolerance)
#   - Eneboliger (111): score >= 80 (permanent residence, single household)
#   - Tomannsbolig (112): score >= 82 (2 households affected)
#   - Rekkehus (113): score >= 85 (multi-unit, shared infrastructure)
#   - Våningshus (121): score >= 85 (many households, critical infrastructure)

set -e

echo "=============================================="
echo "Type-Aware Weak Grid Analysis Reports"
echo "=============================================="

DB_NAME="svakenett"
DB_USER="postgres"

OUTPUT_DIR="/mnt/c/Users/klaus/klauspython/svakenett/data/processed/unified_buildings_$(date +%Y-%m-%d)"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "Output directory: $OUTPUT_DIR"

# ===========================================================================
# Report 1: Prospects by Building Type (with type-aware thresholds)
# ===========================================================================
echo ""
echo "1. Generating type-aware prospect counts..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME > "$OUTPUT_DIR/01_type_aware_prospects.txt" <<'SQL'
\echo '=============================================='
\echo 'Weak Grid Prospects by Building Type'
\echo 'Type-Aware Score Thresholds Applied'
\echo '=============================================='
\echo ''

-- Apply type-aware thresholds
WITH type_thresholds AS (
    SELECT
        bygningstype,
        building_type_name,
        CASE bygningstype
            WHEN 161 THEN 70  -- Cabins (fritidsbygg)
            WHEN 111 THEN 80  -- Single-family homes (enebolig)
            WHEN 112 THEN 82  -- Duplexes (tomannsbolig)
            WHEN 113 THEN 85  -- Townhouses (rekkehus)
            WHEN 121 THEN 85  -- Apartment buildings (våningshus)
        END as score_threshold
    FROM buildings
    GROUP BY bygningstype, building_type_name
),
prospects AS (
    SELECT
        b.bygningstype,
        b.building_type_name,
        b.building_source,
        t.score_threshold,
        COUNT(*) as total_buildings,
        COUNT(b.weak_grid_score) as scored_buildings,
        SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) as prospects,
        ROUND(100.0 * SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) / COUNT(b.weak_grid_score), 1) as prospect_pct,
        ROUND(AVG(CASE WHEN b.weak_grid_score >= t.score_threshold THEN b.weak_grid_score END)::numeric, 1) as avg_prospect_score
    FROM buildings b
    JOIN type_thresholds t ON b.bygningstype = t.bygningstype
    GROUP BY b.bygningstype, b.building_type_name, b.building_source, t.score_threshold
)
SELECT
    bygningstype,
    building_type_name,
    building_source,
    score_threshold as threshold,
    total_buildings,
    scored_buildings,
    prospects,
    prospect_pct as pct_prospects,
    avg_prospect_score as avg_score
FROM prospects
ORDER BY bygningstype;

\echo ''
\echo '[Summary Totals]'

WITH type_thresholds AS (
    SELECT
        bygningstype,
        CASE bygningstype
            WHEN 161 THEN 70
            WHEN 111 THEN 80
            WHEN 112 THEN 82
            WHEN 113 THEN 85
            WHEN 121 THEN 85
        END as score_threshold
    FROM buildings
    GROUP BY bygningstype
)
SELECT
    COUNT(*) as total_buildings,
    COUNT(b.weak_grid_score) as scored_buildings,
    SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) as total_prospects,
    ROUND(100.0 * SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) / COUNT(b.weak_grid_score), 1) as prospect_pct
FROM buildings b
JOIN type_thresholds t ON b.bygningstype = t.bygningstype;
SQL

echo "   ✓ Saved to $OUTPUT_DIR/01_type_aware_prospects.txt"

# ===========================================================================
# Report 2: Geographic Distribution of Prospects
# ===========================================================================
echo ""
echo "2. Generating geographic distribution..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME > "$OUTPUT_DIR/02_geographic_distribution.txt" <<'SQL'
\echo '=============================================='
\echo 'Geographic Distribution of Weak Grid Prospects'
\echo '=============================================='
\echo ''

WITH type_thresholds AS (
    SELECT
        bygningstype,
        CASE bygningstype
            WHEN 161 THEN 70
            WHEN 111 THEN 80
            WHEN 112 THEN 82
            WHEN 113 THEN 85
            WHEN 121 THEN 85
        END as score_threshold
    FROM buildings
    GROUP BY bygningstype
)
SELECT
    COALESCE(b.postal_code, 'Unknown') as postal_code,
    COUNT(*) as total_buildings,
    SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) as prospects,
    ROUND(100.0 * SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) / COUNT(*), 1) as prospect_pct,
    ROUND(AVG(CASE WHEN b.weak_grid_score >= t.score_threshold THEN b.weak_grid_score END)::numeric, 1) as avg_score
FROM buildings b
JOIN type_thresholds t ON b.bygningstype = t.bygningstype
WHERE b.weak_grid_score IS NOT NULL
GROUP BY b.postal_code
HAVING SUM(CASE WHEN b.weak_grid_score >= t.score_threshold THEN 1 ELSE 0 END) > 0
ORDER BY prospects DESC
LIMIT 30;
SQL

echo "   ✓ Saved to $OUTPUT_DIR/02_geographic_distribution.txt"

# ===========================================================================
# Report 3: Score Distribution Analysis
# ===========================================================================
echo ""
echo "3. Generating score distribution analysis..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME > "$OUTPUT_DIR/03_score_distribution.txt" <<'SQL'
\echo '=============================================='
\echo 'Weak Grid Score Distribution'
\echo '=============================================='
\echo ''

SELECT
    bygningstype,
    building_type_name,
    COUNT(*) as total,
    COUNT(weak_grid_score) as scored,
    ROUND(AVG(weak_grid_score)::numeric, 1) as avg_score,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY weak_grid_score)::numeric, 1) as p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY weak_grid_score)::numeric, 1) as median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY weak_grid_score)::numeric, 1) as p75,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY weak_grid_score)::numeric, 1) as p90,
    ROUND(MIN(weak_grid_score)::numeric, 1) as min_score,
    ROUND(MAX(weak_grid_score)::numeric, 1) as max_score
FROM buildings
WHERE weak_grid_score IS NOT NULL
GROUP BY bygningstype, building_type_name
ORDER BY bygningstype;
SQL

echo "   ✓ Saved to $OUTPUT_DIR/03_score_distribution.txt"

# ===========================================================================
# Report 4: Top 100 Prospects Per Building Type
# ===========================================================================
echo ""
echo "4. Generating top prospects per type..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME > "$OUTPUT_DIR/04_top_prospects_per_type.txt" <<'SQL'
\echo '=============================================='
\echo 'Top 100 Prospects Per Building Type'
\echo '=============================================='
\echo ''

WITH type_thresholds AS (
    SELECT
        bygningstype,
        CASE bygningstype
            WHEN 161 THEN 70
            WHEN 111 THEN 80
            WHEN 112 THEN 82
            WHEN 113 THEN 85
            WHEN 121 THEN 85
        END as score_threshold
    FROM buildings
    GROUP BY bygningstype
),
ranked_prospects AS (
    SELECT
        b.bygningstype,
        b.building_type_name,
        b.id,
        b.weak_grid_score,
        b.distance_to_line_m,
        b.grid_density_lines_1km,
        b.voltage_level_kv,
        b.postal_code,
        ST_X(b.geometry) as longitude,
        ST_Y(b.geometry) as latitude,
        t.score_threshold,
        ROW_NUMBER() OVER (PARTITION BY b.bygningstype ORDER BY b.weak_grid_score DESC) as rank_in_type
    FROM buildings b
    JOIN type_thresholds t ON b.bygningstype = t.bygningstype
    WHERE b.weak_grid_score >= t.score_threshold
)
SELECT
    bygningstype,
    building_type_name,
    rank_in_type as rank,
    id,
    ROUND(weak_grid_score::numeric, 1) as score,
    ROUND(distance_to_line_m) as dist_m,
    grid_density_lines_1km as density,
    voltage_level_kv as voltage_kv,
    postal_code,
    ROUND(longitude::numeric, 6) as lon,
    ROUND(latitude::numeric, 6) as lat
FROM ranked_prospects
WHERE rank_in_type <= 100
ORDER BY bygningstype, rank_in_type;
SQL

echo "   ✓ Saved to $OUTPUT_DIR/04_top_prospects_per_type.txt"

# ===========================================================================
# Report 5: Infrastructure Quality by Building Type
# ===========================================================================
echo ""
echo "5. Generating infrastructure quality metrics..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME > "$OUTPUT_DIR/05_infrastructure_quality.txt" <<'SQL'
\echo '=============================================='
\echo 'Grid Infrastructure Quality by Building Type'
\echo '=============================================='
\echo ''

SELECT
    bygningstype,
    building_type_name,
    COUNT(*) as total_buildings,

    -- Distance metrics
    ROUND(AVG(distance_to_line_m)) as avg_dist_m,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_to_line_m)) as median_dist_m,

    -- Grid density
    ROUND(AVG(grid_density_lines_1km), 1) as avg_density,

    -- Voltage distribution
    SUM(CASE WHEN voltage_level_kv >= 132 THEN 1 ELSE 0 END) as high_voltage_count,
    SUM(CASE WHEN voltage_level_kv >= 33 AND voltage_level_kv < 132 THEN 1 ELSE 0 END) as medium_voltage_count,
    SUM(CASE WHEN voltage_level_kv < 33 THEN 1 ELSE 0 END) as low_voltage_count,

    -- Grid age
    ROUND(AVG(grid_age_years), 1) as avg_grid_age_years

FROM buildings
WHERE distance_to_line_m IS NOT NULL
GROUP BY bygningstype, building_type_name
ORDER BY bygningstype;
SQL

echo "   ✓ Saved to $OUTPUT_DIR/05_infrastructure_quality.txt"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "=============================================="
echo "[OK] Type-Aware Reports Generated"
echo "=============================================="
echo ""
echo "Reports saved to: $OUTPUT_DIR"
echo ""
echo "Generated files:"
echo "  1. 01_type_aware_prospects.txt - Prospect counts with type-aware thresholds"
echo "  2. 02_geographic_distribution.txt - Geographic distribution of prospects"
echo "  3. 03_score_distribution.txt - Score distribution by building type"
echo "  4. 04_top_prospects_per_type.txt - Top 100 prospects per building type"
echo "  5. 05_infrastructure_quality.txt - Infrastructure quality metrics"
echo ""
