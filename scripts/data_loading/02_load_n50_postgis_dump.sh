#!/bin/bash
# Load Kartverket N50 PostGIS dump directly into PostgreSQL
# This is the OPTIMAL method - no conversion needed!

set -e  # Exit on error

DUMP_FILE="${1:-data/raw/n50_agder_postgis.dump}"
TEMP_SCHEMA="kartverket_n50"

echo "=========================================="
echo "Loading N50 PostGIS Dump"
echo "=========================================="
echo ""

# Check if dump file exists
if [ ! -f "$DUMP_FILE" ]; then
    echo "❌ Error: Dump file not found: $DUMP_FILE"
    echo ""
    echo "Download from Geonorge.no:"
    echo "  1. Visit: https://kartkatalog.geonorge.no/"
    echo "  2. Search: 'N50 Kartdata'"
    echo "  3. Select: Agder fylke"
    echo "  4. Format: PostGIS - SQL dump"
    echo "  5. Save to: $DUMP_FILE"
    echo ""
    exit 1
fi

echo "✓ Found dump file: $DUMP_FILE"
echo ""

# Check PostgreSQL is running
echo "Checking PostgreSQL connection..."
if ! docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT 1" > /dev/null 2>&1; then
    echo "❌ Error: PostgreSQL not running"
    echo "   Run: docker-compose up -d"
    exit 1
fi
echo "✓ PostgreSQL is running"
echo ""

# Create temporary schema for Kartverket data
echo "Creating temporary schema: $TEMP_SCHEMA..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    DROP SCHEMA IF EXISTS $TEMP_SCHEMA CASCADE;
    CREATE SCHEMA $TEMP_SCHEMA;
" > /dev/null
echo "✓ Schema created"
echo ""

# Detect file format and restore appropriately
echo "Restoring PostGIS dump (this may take 1-2 minutes)..."

if [[ "$DUMP_FILE" == *.sql ]]; then
    # SQL text file - use psql
    echo "Detected SQL text format, using psql..."
    docker exec -i svakenett-postgis psql \
        -U postgres \
        -d svakenett \
        -v ON_ERROR_STOP=1 \
        < "$DUMP_FILE" 2>&1 | tail -20
else
    # Binary dump - use pg_restore
    echo "Detected binary dump format, using pg_restore..."
    docker exec -i svakenett-postgis pg_restore \
        -U postgres \
        -d svakenett \
        --schema=$TEMP_SCHEMA \
        --no-owner \
        --no-acl \
        --verbose \
        < "$DUMP_FILE" 2>&1 | grep -v "^pg_restore: " || true
fi

echo "✓ Dump restored"
echo ""

# Show what tables were created
echo "Tables in temporary schema:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = '$TEMP_SCHEMA'
    ORDER BY tablename;
"
echo ""

# Extract cabins from N50 buildings
echo "Extracting cabins from N50 buildings..."
docker exec svakenett-postgis psql -U postgres -d svakenett <<EOF

-- Insert cabins from Kartverket data into our schema
-- NOTE: Adjust column mapping based on actual N50 schema
INSERT INTO public.cabins (
    geometry,
    building_type,
    postal_code,
    municipality_number,
    data_source,
    created_at
)
SELECT
    -- Convert to WGS84 if needed (N50 is typically UTM33N - EPSG:25833)
    ST_Transform(geom, 4326) as geometry,

    -- Filter for cabins (Norwegian: "fritidsbygg", "hytte", etc.)
    objtype as building_type,

    -- Extract postal code and municipality
    -- NOTE: Column names may vary - check actual schema!
    postnummer as postal_code,
    kommunenummer as municipality_number,

    'Kartverket N50' as data_source,
    CURRENT_TIMESTAMP as created_at

FROM $TEMP_SCHEMA.n50_bygninger  -- Adjust table name if different!

WHERE
    -- Filter for cabins only
    objtype ILIKE '%fritid%'
    OR objtype ILIKE '%hytte%'
    OR objtype ILIKE '%cabin%'

    -- Optional: Filter by municipality (Agder codes: 4201-4228, 901-904)
    -- AND kommunenummer LIKE '42%' OR kommunenummer LIKE '90%'
;

-- Show results
SELECT
    COUNT(*) as total_cabins_loaded,
    COUNT(DISTINCT postal_code) as unique_postal_codes,
    COUNT(DISTINCT municipality_number) as unique_municipalities
FROM public.cabins;

EOF

echo ""
echo "✓ Cabins extracted to public.cabins table"
echo ""

# Clean up temporary schema
echo "Cleaning up temporary schema..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    DROP SCHEMA $TEMP_SCHEMA CASCADE;
" > /dev/null
echo "✓ Temporary schema dropped"
echo ""

echo "=========================================="
echo "✓ N50 PostGIS dump loaded successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Verify data in QGIS"
echo "  2. Download KILE statistics (scripts/03_download_kile_data.py)"
echo "  3. Calculate scores (Day 8-10)"
echo ""
