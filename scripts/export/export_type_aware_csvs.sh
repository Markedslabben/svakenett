#!/bin/bash
# Export type-aware weak grid prospect CSVs
# Creates separate CSV files for each building type with type-specific thresholds

set -e

echo "=============================================="
echo "Exporting Type-Aware Prospect CSVs"
echo "=============================================="

DB_NAME="svakenett"
DB_USER="postgres"

OUTPUT_DIR="/mnt/c/Users/klaus/klauspython/svakenett/data/processed/unified_buildings_$(date +%Y-%m-%d)"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "Output directory: $OUTPUT_DIR"

# ===========================================================================
# CSV 1: All Buildings with Scores
# ===========================================================================
echo ""
echo "1. Exporting all scored buildings..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/all_buildings_scored.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        building_source,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(distance_to_transformer_m) as distance_to_transformer_m,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE bygningstype
            WHEN 161 THEN 70
            WHEN 111 THEN 80
            WHEN 112 THEN 82
            WHEN 113 THEN 85
            WHEN 121 THEN 85
        END as type_threshold,
        CASE
            WHEN weak_grid_score >= (CASE bygningstype
                WHEN 161 THEN 70
                WHEN 111 THEN 80
                WHEN 112 THEN 82
                WHEN 113 THEN 85
                WHEN 121 THEN 85
            END) THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= (CASE bygningstype
                WHEN 161 THEN 60
                WHEN 111 THEN 70
                WHEN 112 THEN 72
                WHEN 113 THEN 75
                WHEN 121 THEN 75
            END) THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC, bygningstype
) TO STDOUT WITH CSV HEADER;
SQL

echo "   ✓ Exported $(wc -l < "$OUTPUT_DIR/all_buildings_scored.csv") buildings to all_buildings_scored.csv"

# ===========================================================================
# CSV 2: High Prospects Only (meets type threshold)
# ===========================================================================
echo ""
echo "2. Exporting high prospects only..."

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/high_prospects_only.csv"
COPY (
    WITH type_thresholds AS (
        SELECT
            bygningstype,
            CASE bygningstype
                WHEN 161 THEN 70
                WHEN 111 THEN 80
                WHEN 112 THEN 82
                WHEN 113 THEN 85
                WHEN 121 THEN 85
            END as threshold
        FROM buildings
        GROUP BY bygningstype
    )
    SELECT
        b.id,
        b.bygningstype,
        b.building_type_name,
        b.building_source,
        b.postal_code,
        b.kommunenummer,
        b.kommunenavn,
        ROUND(ST_Y(b.geometry)::numeric, 6) as latitude,
        ROUND(ST_X(b.geometry)::numeric, 6) as longitude,
        ROUND(b.distance_to_line_m) as distance_to_line_m,
        b.grid_density_lines_1km,
        b.voltage_level_kv,
        ROUND(b.grid_age_years::numeric, 1) as grid_age_years,
        ROUND(b.distance_to_transformer_m) as distance_to_transformer_m,
        ROUND(b.weak_grid_score::numeric, 1) as weak_grid_score,
        t.threshold as type_threshold
    FROM buildings b
    JOIN type_thresholds t ON b.bygningstype = t.bygningstype
    WHERE b.weak_grid_score >= t.threshold
    ORDER BY b.weak_grid_score DESC, b.bygningstype
) TO STDOUT WITH CSV HEADER;
SQL

echo "   ✓ Exported $(wc -l < "$OUTPUT_DIR/high_prospects_only.csv") high prospects to high_prospects_only.csv"

# ===========================================================================
# CSV 3-7: Separate CSV per Building Type
# ===========================================================================
echo ""
echo "3. Exporting by building type..."

# Cabins (161)
echo "   - Cabins (fritidsbygg)..."
PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/cabins_161_prospects.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE
            WHEN weak_grid_score >= 70 THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= 60 THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE bygningstype = 161 AND weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC
) TO STDOUT WITH CSV HEADER;
SQL

# Single-family homes (111)
echo "   - Single-family homes (eneboliger)..."
PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/enebolig_111_prospects.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE
            WHEN weak_grid_score >= 80 THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= 70 THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE bygningstype = 111 AND weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC
) TO STDOUT WITH CSV HEADER;
SQL

# Duplexes (112)
echo "   - Duplexes (tomannsboliger)..."
PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/tomannsbolig_112_prospects.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE
            WHEN weak_grid_score >= 82 THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= 72 THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE bygningstype = 112 AND weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC
) TO STDOUT WITH CSV HEADER;
SQL

# Townhouses (113)
echo "   - Townhouses (rekkehus)..."
PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/rekkehus_113_prospects.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE
            WHEN weak_grid_score >= 85 THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= 75 THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE bygningstype = 113 AND weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC
) TO STDOUT WITH CSV HEADER;
SQL

# Apartment buildings (121)
echo "   - Apartment buildings (våningshus)..."
PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME <<SQL > "$OUTPUT_DIR/vaningshus_121_prospects.csv"
COPY (
    SELECT
        id,
        bygningstype,
        building_type_name,
        postal_code,
        kommunenummer,
        kommunenavn,
        ROUND(ST_Y(geometry)::numeric, 6) as latitude,
        ROUND(ST_X(geometry)::numeric, 6) as longitude,
        ROUND(distance_to_line_m) as distance_to_line_m,
        grid_density_lines_1km,
        voltage_level_kv,
        ROUND(grid_age_years::numeric, 1) as grid_age_years,
        ROUND(weak_grid_score::numeric, 1) as weak_grid_score,
        CASE
            WHEN weak_grid_score >= 85 THEN 'HIGH_PROSPECT'
            WHEN weak_grid_score >= 75 THEN 'MEDIUM_PROSPECT'
            ELSE 'LOW_PROSPECT'
        END as prospect_category
    FROM buildings
    WHERE bygningstype = 121 AND weak_grid_score IS NOT NULL
    ORDER BY weak_grid_score DESC
) TO STDOUT WITH CSV HEADER;
SQL

echo "   ✓ Type-specific CSVs exported"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "=============================================="
echo "[OK] CSV Export Complete"
echo "=============================================="
echo ""
echo "Exported files to: $OUTPUT_DIR"
echo ""
ls -lh "$OUTPUT_DIR"/*.csv
echo ""
