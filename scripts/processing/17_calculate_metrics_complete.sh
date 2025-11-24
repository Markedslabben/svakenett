#!/bin/bash
# Calculate grid infrastructure metrics for all cabins
# Uses batch processing to handle 37K cabins efficiently

set -e  # Exit on error

echo "=========================================="
echo "Calculating Grid Infrastructure Metrics"
echo "=========================================="

DB_CONTAINER="svakenett-postgis"
DB_NAME="svakenett"
DB_USER="postgres"

# Batch size for processing (learned from 11_assign_by_batch.sh)
BATCH_SIZE=1000

# Check database connection
if ! docker ps | grep -q $DB_CONTAINER; then
    echo "✗ Error: PostgreSQL container not running"
    exit 1
fi

# Get total cabin count
echo ""
echo "0. Checking cabin count..."
total_cabins=$(docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM cabins;")
echo "Total cabins to process: $total_cabins"

# Calculate number of batches
num_batches=$(( (total_cabins + BATCH_SIZE - 1) / BATCH_SIZE ))
echo "Processing in $num_batches batches of $BATCH_SIZE cabins each"

# ===========================================================================
# METRIC 1: Distance to Nearest Power Line
# ===========================================================================
echo ""
echo "1. Calculating distance to nearest power line..."
echo "   (This is the PRIMARY metric - may take 5-10 minutes)"

for ((batch=0; batch<num_batches; batch++)); do
    offset=$((batch * BATCH_SIZE))
    progress=$((batch + 1))

    echo -ne "   Batch $progress/$num_batches (offset $offset)...\r"

    docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL >/dev/null 2>&1
WITH batch_cabins AS (
    SELECT id, geometry
    FROM cabins
    ORDER BY id
    LIMIT $BATCH_SIZE OFFSET $offset
),
nearest_lines AS (
    SELECT
        bc.id as cabin_id,
        pl.id as line_id,
        ST_Distance(bc.geometry::geography, pl.geometry::geography) as distance_m,
        pl.voltage_kv,
        pl.owner_orgnr,
        ROW_NUMBER() OVER (PARTITION BY bc.id ORDER BY ST_Distance(bc.geometry, pl.geometry)) as rn
    FROM batch_cabins bc
    CROSS JOIN LATERAL (
        SELECT id, geometry, voltage_kv, owner_orgnr
        FROM power_lines_new
        ORDER BY bc.geometry <-> geometry
        LIMIT 1
    ) pl
)
UPDATE cabins c
SET
    distance_to_line_m = ROUND(nl.distance_m::numeric, 2),
    voltage_level_kv = nl.voltage_kv,
    nearest_line_owner = nl.owner_orgnr
FROM nearest_lines nl
WHERE c.id = nl.cabin_id AND nl.rn = 1;
SQL
done

echo ""
echo "   ✓ Distance calculation complete"

# ===========================================================================
# METRIC 2: Grid Density (lines within 1km)
# ===========================================================================
echo ""
echo "2. Calculating grid density within 1km radius..."

for ((batch=0; batch<num_batches; batch++)); do
    offset=$((batch * BATCH_SIZE))
    progress=$((batch + 1))

    echo -ne "   Batch $progress/$num_batches (offset $offset)...\r"

    docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL >/dev/null 2>&1
WITH batch_cabins AS (
    SELECT id, geometry
    FROM cabins
    ORDER BY id
    LIMIT $BATCH_SIZE OFFSET $offset
),
density_calc AS (
    SELECT
        bc.id as cabin_id,
        COUNT(pl.id) as line_count,
        COALESCE(SUM(ST_Length(pl.geometry::geography)) / 1000, 0) as total_length_km
    FROM batch_cabins bc
    LEFT JOIN power_lines_new pl
        ON ST_DWithin(bc.geometry::geography, pl.geometry::geography, 1000)
    GROUP BY bc.id
)
UPDATE cabins c
SET
    grid_density_lines_1km = dc.line_count,
    grid_density_length_km = ROUND(dc.total_length_km::numeric, 2)
FROM density_calc dc
WHERE c.id = dc.cabin_id;
SQL
done

echo ""
echo "   ✓ Grid density calculation complete"

# ===========================================================================
# METRIC 3: Grid Age (average age of nearby lines)
# ===========================================================================
echo ""
echo "3. Calculating average grid age within 1km..."

for ((batch=0; batch<num_batches; batch++)); do
    offset=$((batch * BATCH_SIZE))
    progress=$((batch + 1))

    echo -ne "   Batch $progress/$num_batches (offset $offset)...\r"

    docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL >/dev/null 2>&1
WITH batch_cabins AS (
    SELECT id, geometry
    FROM cabins
    ORDER BY id
    LIMIT $BATCH_SIZE OFFSET $offset
),
age_calc AS (
    SELECT
        bc.id as cabin_id,
        ROUND(AVG(2025 - pl.year_built)::numeric, 1) as avg_age_years
    FROM batch_cabins bc
    LEFT JOIN power_lines_new pl
        ON ST_DWithin(bc.geometry::geography, pl.geometry::geography, 1000)
        AND pl.year_built IS NOT NULL
    GROUP BY bc.id
)
UPDATE cabins c
SET grid_age_years = ac.avg_age_years
FROM age_calc ac
WHERE c.id = ac.cabin_id;
SQL
done

echo ""
echo "   ✓ Grid age calculation complete"

# ===========================================================================
# METRIC 4: Distance to Transformer (optional - for future use)
# ===========================================================================
echo ""
echo "4. Calculating distance to nearest transformer..."

for ((batch=0; batch<num_batches; batch++)); do
    offset=$((batch * BATCH_SIZE))
    progress=$((batch + 1))

    echo -ne "   Batch $progress/$num_batches (offset $offset)...\r"

    docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<SQL >/dev/null 2>&1
WITH batch_cabins AS (
    SELECT id, geometry
    FROM cabins
    ORDER BY id
    LIMIT $BATCH_SIZE OFFSET $offset
),
nearest_transformers AS (
    SELECT
        bc.id as cabin_id,
        ST_Distance(bc.geometry::geography, t.geometry::geography) as distance_m,
        ROW_NUMBER() OVER (PARTITION BY bc.id ORDER BY ST_Distance(bc.geometry, t.geometry)) as rn
    FROM batch_cabins bc
    CROSS JOIN LATERAL (
        SELECT id, geometry
        FROM transformers_new
        ORDER BY bc.geometry <-> geometry
        LIMIT 1
    ) t
)
UPDATE cabins c
SET distance_to_transformer_m = ROUND(nt.distance_m::numeric, 2)
FROM nearest_transformers nt
WHERE c.id = nt.cabin_id AND nt.rn = 1;
SQL
done

echo ""
echo "   ✓ Transformer distance calculation complete"

# ===========================================================================
# Verification and Statistics
# ===========================================================================
echo ""
echo "5. Verification - Metric completeness:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    COUNT(*) as total_cabins,
    COUNT(distance_to_line_m) as has_distance,
    COUNT(grid_density_lines_1km) as has_density,
    COUNT(grid_age_years) as has_age,
    COUNT(voltage_level_kv) as has_voltage,
    ROUND(100.0 * COUNT(distance_to_line_m) / COUNT(*), 1) as distance_pct
FROM cabins;
SQL

echo ""
echo "6. Metric statistics:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    'Distance to line (m)' as metric,
    ROUND(MIN(distance_to_line_m), 0) as min_value,
    ROUND(AVG(distance_to_line_m), 0) as avg_value,
    ROUND(MAX(distance_to_line_m), 0) as max_value,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_to_line_m), 0) as median_value
FROM cabins
WHERE distance_to_line_m IS NOT NULL

UNION ALL

SELECT
    'Grid density (lines)' as metric,
    MIN(grid_density_lines_1km) as min_value,
    ROUND(AVG(grid_density_lines_1km), 1) as avg_value,
    MAX(grid_density_lines_1km) as max_value,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY grid_density_lines_1km) as median_value
FROM cabins
WHERE grid_density_lines_1km IS NOT NULL

UNION ALL

SELECT
    'Grid age (years)' as metric,
    ROUND(MIN(grid_age_years), 0) as min_value,
    ROUND(AVG(grid_age_years), 0) as avg_value,
    ROUND(MAX(grid_age_years), 0) as max_value,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY grid_age_years), 0) as median_value
FROM cabins
WHERE grid_age_years IS NOT NULL;
SQL

echo ""
echo "7. Sample cabins with calculated metrics:"
docker exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME <<'SQL'
SELECT
    id,
    postal_code,
    ROUND(distance_to_line_m) as dist_m,
    grid_density_lines_1km as density,
    ROUND(grid_age_years, 1) as age_yrs,
    voltage_level_kv as voltage_kv,
    ST_X(geometry) as lon,
    ST_Y(geometry) as lat
FROM cabins
WHERE distance_to_line_m IS NOT NULL
ORDER BY distance_to_line_m DESC
LIMIT 10;
SQL

echo ""
echo "=========================================="
echo "[OK] Metrics calculation complete!"
echo "=========================================="
echo ""
echo "Next step: Run ./scripts/15_apply_scoring.sh"
