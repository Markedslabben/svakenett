#!/bin/bash
# Load grid company service areas into PostgreSQL

GEOJSON_FILE="data/grid_companies/service_areas.geojson"

echo "=========================================="
echo "Loading Grid Company Service Areas to PostgreSQL"
echo "=========================================="

# Create temporary table for NVE data
echo ""
echo "1. Creating temporary table for NVE service areas..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
DROP TABLE IF EXISTS temp_nve_service_areas;
CREATE TABLE temp_nve_service_areas (
    navn VARCHAR(200),
    eier_id VARCHAR(50),
    konstype VARCHAR(20),
    eiertype VARCHAR(20),
    service_area_polygon GEOMETRY(MultiPolygon, 4326)
);
"

# Load GeoJSON using Python
echo ""
echo "2. Parsing GeoJSON and loading to temp table..."
python3 << 'EOF'
import json
import subprocess

with open('data/grid_companies/service_areas.geojson', 'r') as f:
    data = json.load(f)

print(f"   Processing {len(data['features'])} service areas...")

sql_statements = []
for feature in data['features']:
    props = feature['properties']
    geom = feature['geometry']

    # Extract fields
    navn = props.get('NAVN', '').replace("'", "''")
    eier_id = str(props.get('EIER_ID', ''))
    konstype = props.get('KONSTYPE', '').replace("'", "''")
    eiertype = props.get('EIERTYPE', '').replace("'", "''")

    # Convert geometry to GeoJSON string
    geom_json = json.dumps(geom).replace("'", "''")

    # Create INSERT statement
    sql = f"""INSERT INTO temp_nve_service_areas (navn, eier_id, konstype, eiertype, service_area_polygon)
    VALUES ('{navn}', '{eier_id}', '{konstype}', '{eiertype}', ST_Multi(ST_GeomFromGeoJSON('{geom_json}')));"""

    sql_statements.append(sql)

# Save to temp file
with open('/tmp/nve_service_areas.sql', 'w') as f:
    f.write('\n'.join(sql_statements))

print(f"   Generated {len(sql_statements)} INSERT statements")
EOF

# Load into PostgreSQL
echo ""
echo "3. Loading data to temporary table..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/nve_service_areas.sql 2>&1 | grep -E "INSERT|ERROR" | tail -5

# Clean up temp file
rm /tmp/nve_service_areas.sql

# Verify temp table
echo ""
echo "4. Verifying temporary table..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT COUNT(*) as nve_service_areas FROM temp_nve_service_areas;
"

# Match and update grid_companies table
echo ""
echo "5. Matching NVE data to existing grid_companies (by company_code)..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
UPDATE grid_companies gc
SET service_area_polygon = nve.service_area_polygon
FROM temp_nve_service_areas nve
WHERE gc.company_code = nve.eier_id;
"

# Check how many matched
echo ""
echo "6. Checking match results..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM grid_companies) as total_kile_companies,
    (SELECT COUNT(*) FROM temp_nve_service_areas) as total_nve_areas,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NOT NULL) as matched_companies,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NULL) as unmatched_companies;
"

# Show matched companies
echo ""
echo "7. Sample matched companies:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    company_name,
    company_code,
    CASE WHEN service_area_polygon IS NOT NULL THEN 'YES' ELSE 'NO' END as has_service_area,
    kile_cost_nok
FROM grid_companies
WHERE kile_cost_nok > 10000
ORDER BY kile_cost_nok DESC
LIMIT 10;
"

# Clean up temporary table
echo ""
echo "8. Cleaning up temporary table..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
DROP TABLE temp_nve_service_areas;
"

echo ""
echo "=========================================="
echo "[OK] Grid company service areas loaded!"
echo "=========================================="
