#!/bin/bash
# Load complete NVE infrastructure data from QGIS geodatabase
# This replaces the partial data with full dataset

set -e

echo "=========================================="
echo "Loading Complete NVE Infrastructure Data"
echo "=========================================="

DB_CONTAINER="svakenett-postgis"
DB_NAME="svakenett"
DB_USER="postgres"
GDB_PATH="/mnt/c/Users/klaus/klauspython/qgis/svakenett/NVEKartdata/NVEData.gdb"

# Check if geodatabase exists
if [ ! -d "$GDB_PATH" ]; then
    echo "✗ Error: Geodatabase not found at $GDB_PATH"
    exit 1
fi

# Check database connection
if ! docker ps | grep -q $DB_CONTAINER; then
    echo "✗ Error: PostgreSQL container not running"
    exit 1
fi

echo ""
echo "1. Backing up existing data..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
-- Backup existing tables (in case we need to rollback)
DROP TABLE IF EXISTS power_lines_backup;
DROP TABLE IF EXISTS transformers_backup;

CREATE TABLE power_lines_backup AS SELECT * FROM power_lines;
CREATE TABLE transformers_backup AS SELECT * FROM transformers;

SELECT
    'power_lines_backup' as table_name,
    COUNT(*) as records
FROM power_lines_backup
UNION ALL
SELECT
    'transformers_backup',
    COUNT(*)
FROM transformers_backup;
SQL

echo ""
echo "2. Dropping old infrastructure tables..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
DROP TABLE IF EXISTS power_lines;
DROP TABLE IF EXISTS transformers;
SQL

echo ""
echo "3. Loading Kraftlinje (power lines) - 9,715 features..."
ogr2ogr -f "PostgreSQL" \
    PG:"host=localhost port=5432 dbname=$DB_NAME user=$DB_USER" \
    "$GDB_PATH" \
    "Kraftlinje" \
    -nln power_lines \
    -lco GEOMETRY_NAME=geometry \
    -lco FID=id \
    -t_srs EPSG:4326 \
    -progress

echo ""
echo "4. Loading Transformatorstasjon (transformers) - 106 features..."
ogr2ogr -f "PostgreSQL" \
    PG:"host=localhost port=5432 dbname=$DB_NAME user=$DB_USER" \
    "$GDB_PATH" \
    "Transformatorstasjon" \
    -nln transformers \
    -lco GEOMETRY_NAME=geometry \
    -lco FID=id \
    -t_srs EPSG:4326 \
    -progress

echo ""
echo "5. Creating spatial indexes..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
-- Spatial indexes for performance
CREATE INDEX idx_power_lines_geom ON power_lines USING GIST(geometry);
CREATE INDEX idx_transformers_geom ON transformers USING GIST(geometry);

-- Regular indexes
CREATE INDEX idx_power_lines_voltage ON power_lines(spenning_kv);
CREATE INDEX idx_power_lines_year ON power_lines(driftsattaar);
SQL

echo ""
echo "6. Adding standardized columns (matching old schema)..."
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
-- Add voltage_kv as alias for spenning_kv
ALTER TABLE power_lines ADD COLUMN voltage_kv REAL;
UPDATE power_lines SET voltage_kv = spenning_kv;

-- Add year_built as alias for driftsattaar
ALTER TABLE power_lines ADD COLUMN year_built INTEGER;
UPDATE power_lines SET year_built = driftsattaar;

-- Add owner_orgnr as alias for eierorgnr
ALTER TABLE power_lines ADD COLUMN owner_orgnr INTEGER;
UPDATE power_lines SET owner_orgnr = eierorgnr;
SQL

echo ""
echo "7. Verification - Infrastructure completeness:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
SELECT
    'Power Lines' as layer,
    COUNT(*) as features,
    MIN(spenning_kv) as min_voltage_kv,
    MAX(spenning_kv) as max_voltage_kv,
    MIN(driftsattaar) as oldest_year,
    MAX(driftsattaar) as newest_year
FROM power_lines
WHERE spenning_kv IS NOT NULL

UNION ALL

SELECT
    'Transformers',
    COUNT(*),
    NULL,
    NULL,
    NULL,
    NULL
FROM transformers;
SQL

echo ""
echo "8. Voltage distribution:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL
SELECT
    spenning_kv as voltage_kv,
    COUNT(*) as line_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM power_lines
GROUP BY spenning_kv
ORDER BY spenning_kv DESC;
SQL

echo ""
echo "=========================================="
echo "[OK] Complete NVE Data Loaded!"
echo "=========================================="
echo ""
echo "Next step: Run ./scripts/processing/14_calculate_metrics.sh"
echo "           to recalculate all cabin metrics with complete data"
