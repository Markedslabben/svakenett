#!/bin/bash
# Inspect N50 schema after loading SQL file

echo "=========================================="
echo "N50 Schema Inspection"
echo "=========================================="
echo ""

echo "1. All schemas in database:"
echo "----------------------------"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    SELECT schema_name
    FROM information_schema.schemata
    ORDER BY schema_name;
"
echo ""

echo "2. All tables (all schemas):"
echo "----------------------------"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    SELECT schemaname, tablename
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY schemaname, tablename;
"
echo ""

echo "3. Tables with 'bygg' in name (buildings):"
echo "-------------------------------------------"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    SELECT schemaname, tablename,
           (SELECT COUNT(*) FROM pg_class WHERE relname = tablename) as row_count_estimate
    FROM pg_tables
    WHERE tablename ILIKE '%bygg%'
    ORDER BY schemaname, tablename;
"
echo ""

echo "4. Columns in first building table found:"
echo "-----------------------------------------"
docker exec svakenett-postgis psql -U postgres -d svakenett <<'EOF'
DO $$
DECLARE
    tbl_schema TEXT;
    tbl_name TEXT;
BEGIN
    SELECT schemaname, tablename INTO tbl_schema, tbl_name
    FROM pg_tables
    WHERE tablename ILIKE '%bygg%'
    LIMIT 1;

    IF tbl_name IS NOT NULL THEN
        RAISE NOTICE 'Table: %.%', tbl_schema, tbl_name;
        EXECUTE format('SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = %L AND table_name = %L ORDER BY ordinal_position', tbl_schema, tbl_name);
    ELSE
        RAISE NOTICE 'No building table found';
    END IF;
END $$;
EOF
echo ""

echo "5. Sample objtype values (building types):"
echo "-------------------------------------------"
BUILDING_TABLE=$(docker exec svakenett-postgis psql -U postgres -d svakenett -t -c "
    SELECT schemaname || '.' || tablename
    FROM pg_tables
    WHERE tablename ILIKE '%bygg%'
    LIMIT 1;
" | xargs)

if [ ! -z "$BUILDING_TABLE" ]; then
    echo "Sampling from: $BUILDING_TABLE"
    docker exec svakenett-postgis psql -U postgres -d svakenett -c "
        SELECT objtype, COUNT(*) as count
        FROM $BUILDING_TABLE
        GROUP BY objtype
        ORDER BY count DESC
        LIMIT 20;
    "
else
    echo "No building table found to sample from"
fi

echo ""
echo "=========================================="
echo "Inspection complete"
echo "=========================================="
