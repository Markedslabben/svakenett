#!/bin/bash
# Load NVE grid infrastructure GeoJSON data into PostGIS database
# Loads 4 tables: power_lines, power_poles, cables, transformers

set -e  # Exit on error

echo "=========================================="
echo "Loading Grid Infrastructure to PostGIS"
echo "=========================================="

# Database connection
DB_CONTAINER="svakenett-postgis"
DB_NAME="svakenett"
DB_USER="postgres"

# Check if Docker container is running
if ! docker ps | grep -q $DB_CONTAINER; then
    echo "✗ Error: PostgreSQL container '$DB_CONTAINER' is not running"
    echo "  Start it with: docker-compose up -d"
    exit 1
fi

# Check if data files exist
DATA_DIR="data/nve_infrastructure"
if [ ! -d "$DATA_DIR" ]; then
    echo "✗ Error: Data directory '$DATA_DIR' not found"
    echo "  Run ./scripts/12_download_grid_infrastructure.sh first"
    exit 1
fi

required_files=(
    "$DATA_DIR/power_lines.geojson"
    "$DATA_DIR/power_poles.geojson"
    "$DATA_DIR/cables.geojson"
    "$DATA_DIR/transformers.geojson"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "✗ Error: Required file not found: $file"
        exit 1
    fi
done

echo "✓ All required data files found"

# Create schema (tables, indexes, functions)
echo ""
echo "1. Creating database schema..."
docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME < docs/DATABASE_SCHEMA.sql

if [ $? -eq 0 ]; then
    echo "✓ Schema created successfully"
else
    echo "✗ Error creating schema"
    exit 1
fi

# Function to load a GeoJSON file into PostGIS
load_geojson() {
    local geojson_file=$1
    local table_name=$2
    local field_mapping=$3

    echo ""
    echo "Loading $table_name from $(basename $geojson_file)..."

    # Copy file into container
    docker cp "$geojson_file" $DB_CONTAINER:/tmp/data.geojson

    # Use ogr2ogr to load GeoJSON into PostGIS
    # -append: add to existing table
    # -update: update existing data
    # -f "PostgreSQL": output format
    # PG:"connection string": database connection
    docker exec $DB_CONTAINER ogr2ogr \
        -f "PostgreSQL" \
        -nln "$table_name" \
        -lco GEOMETRY_NAME=geometry \
        -lco FID=id \
        -overwrite \
        -t_srs EPSG:4326 \
        PG:"host=localhost user=$DB_USER dbname=$DB_NAME password=$DB_USER" \
        /tmp/data.geojson

    if [ $? -eq 0 ]; then
        # Get row count
        row_count=$(docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM $table_name;")
        echo "✓ Loaded $row_count rows into $table_name"
    else
        echo "✗ Error loading $table_name"
        return 1
    fi
}

# Load each layer into its respective table
echo ""
echo "2. Loading GeoJSON data to PostGIS tables..."

# Power Lines (Layer 2: Distribusjonsnett)
load_geojson "$DATA_DIR/power_lines.geojson" "power_lines_raw"

# Transform and clean power_lines data
echo ""
echo "3. Transforming power_lines data..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
-- Clear existing data
TRUNCATE power_lines;

-- Insert cleaned data with field mapping
INSERT INTO power_lines (
    geometry,
    voltage_kv,
    line_length_m,
    owner_orgnr,
    owner_name,
    year_built,
    line_type
)
SELECT
    ST_Transform(wkb_geometry, 4326) as geometry,
    CASE
        WHEN spenning IS NOT NULL THEN CAST(spenning AS INTEGER)
        ELSE NULL
    END as voltage_kv,
    ST_Length(ST_Transform(wkb_geometry, 4326)::geography) as line_length_m,
    eier_orgnr as owner_orgnr,
    eier as owner_name,
    CASE
        WHEN aar IS NOT NULL AND aar > 1900 AND aar < 2030 THEN CAST(aar AS INTEGER)
        ELSE NULL
    END as year_built,
    anleggstype as line_type
FROM power_lines_raw
WHERE wkb_geometry IS NOT NULL;

-- Drop raw table
DROP TABLE IF EXISTS power_lines_raw;
SQL

echo "✓ Power lines transformed"

# Power Poles (Layer 4: Master og stolper)
load_geojson "$DATA_DIR/power_poles.geojson" "power_poles_raw"

echo ""
echo "4. Transforming power_poles data..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
TRUNCATE power_poles;

INSERT INTO power_poles (
    geometry,
    owner_orgnr,
    owner_name,
    year_built,
    pole_type
)
SELECT
    ST_Transform(wkb_geometry, 4326) as geometry,
    eier_orgnr as owner_orgnr,
    eier as owner_name,
    CASE
        WHEN aar IS NOT NULL AND aar > 1900 AND aar < 2030 THEN CAST(aar AS INTEGER)
        ELSE NULL
    END as year_built,
    anleggstype as pole_type
FROM power_poles_raw
WHERE wkb_geometry IS NOT NULL;

DROP TABLE IF EXISTS power_poles_raw;
SQL

echo "✓ Power poles transformed"

# Cables (Layer 3: Sjøkabler)
load_geojson "$DATA_DIR/cables.geojson" "cables_raw"

echo ""
echo "5. Transforming cables data..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
TRUNCATE cables;

INSERT INTO cables (
    geometry,
    cable_type,
    voltage_kv,
    owner_orgnr,
    owner_name,
    year_built,
    cable_length_m
)
SELECT
    ST_Transform(wkb_geometry, 4326) as geometry,
    anleggstype as cable_type,
    CASE
        WHEN spenning IS NOT NULL THEN CAST(spenning AS INTEGER)
        ELSE NULL
    END as voltage_kv,
    eier_orgnr as owner_orgnr,
    eier as owner_name,
    CASE
        WHEN aar IS NOT NULL AND aar > 1900 AND aar < 2030 THEN CAST(aar AS INTEGER)
        ELSE NULL
    END as year_built,
    ST_Length(ST_Transform(wkb_geometry, 4326)::geography) as cable_length_m
FROM cables_raw
WHERE wkb_geometry IS NOT NULL;

DROP TABLE IF EXISTS cables_raw;
SQL

echo "✓ Cables transformed"

# Transformers (Layer 5: Transformatorstasjoner)
load_geojson "$DATA_DIR/transformers.geojson" "transformers_raw"

echo ""
echo "6. Transforming transformers data..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
TRUNCATE transformers;

INSERT INTO transformers (
    geometry,
    owner_orgnr,
    owner_name,
    year_built,
    station_type
)
SELECT
    ST_Transform(wkb_geometry, 4326) as geometry,
    eier_orgnr as owner_orgnr,
    eier as owner_name,
    CASE
        WHEN aar IS NOT NULL AND aar > 1900 AND aar < 2030 THEN CAST(aar AS INTEGER)
        ELSE NULL
    END as year_built,
    anleggstype as station_type
FROM transformers_raw
WHERE wkb_geometry IS NOT NULL;

DROP TABLE IF EXISTS transformers_raw;
SQL

echo "✓ Transformers transformed"

# Verify data load
echo ""
echo "7. Verifying data load..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    'power_lines' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT owner_orgnr) as unique_owners,
    ROUND(AVG(voltage_kv), 0) as avg_voltage_kv,
    ROUND(AVG(2025 - year_built), 1) as avg_age_years
FROM power_lines

UNION ALL

SELECT
    'power_poles' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT owner_orgnr) as unique_owners,
    NULL as avg_voltage_kv,
    ROUND(AVG(2025 - year_built), 1) as avg_age_years
FROM power_poles

UNION ALL

SELECT
    'cables' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT owner_orgnr) as unique_owners,
    ROUND(AVG(voltage_kv), 0) as avg_voltage_kv,
    ROUND(AVG(2025 - year_built), 1) as avg_age_years
FROM cables

UNION ALL

SELECT
    'transformers' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT owner_orgnr) as unique_owners,
    NULL as avg_voltage_kv,
    ROUND(AVG(2025 - year_built), 1) as avg_age_years
FROM transformers;
SQL

echo ""
echo "=========================================="
echo "[OK] Grid infrastructure loaded!"
echo "=========================================="
echo ""
echo "Next step: Run ./scripts/14_calculate_metrics.sh"
