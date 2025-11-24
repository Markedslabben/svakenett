#!/bin/bash
# Load postal code geometries from JSON into PostgreSQL

JSON_FILE="data/postal_codes/postal-codes.json"

echo "=========================================="
echo "Loading Postal Code Geometries to PostgreSQL"
echo "=========================================="

# Generate SQL file directly
echo ""
echo "1. Generating SQL INSERT statements..."

python3 << 'EOF' > /tmp/postal_codes_insert.sql
import json
import sys

JSON_FILE = "data/postal_codes/postal-codes.json"

with open(JSON_FILE, 'r', encoding='utf-8') as f:
    data = json.load(f)

postal_codes_with_geom = []
for code, entry in data.items():
    if entry.get('geojson'):
        postal_codes_with_geom.append({
            'code': code,
            'name': entry.get('poststed', ''),
            'municipality_code': entry.get('kommunenummer', ''),
            'geojson': entry.get('geojson')
        })

print(f"-- Generated {len(postal_codes_with_geom)} postal code INSERT statements", file=sys.stderr)

# Generate SQL INSERT statements
for i, pc in enumerate(postal_codes_with_geom, 1):
    if i % 500 == 0:
        print(f"-- Processing {i}/{len(postal_codes_with_geom)}...", file=sys.stderr)

    # Escape single quotes
    name = pc['name'].replace("'", "''")

    # Extract just the geometry object, not the full Feature
    geometry_obj = pc['geojson'].get('geometry')
    geojson_str = json.dumps(geometry_obj).replace("'", "''")

    # Set municipality_number to NULL for now (municipalities table not loaded yet)
    sql = f"""INSERT INTO postal_codes (postal_code, postal_name, municipality_number, geometry) VALUES ('{pc['code']}', '{name}', NULL, ST_GeomFromGeoJSON('{geojson_str}'));"""

    print(sql)

print(f"-- Completed generating {len(postal_codes_with_geom)} statements", file=sys.stderr)
EOF

echo "   SQL file generated at /tmp/postal_codes_insert.sql"

# Clear existing data
echo ""
echo "2. Clearing existing postal_codes data..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "DELETE FROM postal_codes;"

# Load data
echo ""
echo "3. Loading data to database (this may take 1-2 minutes)..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/postal_codes_insert.sql 2>&1 | grep -E "INSERT|ERROR" | tail -10

# Clean up temp file
rm /tmp/postal_codes_insert.sql

# Verify
echo ""
echo "4. Verifying data..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT COUNT(*) as total_postal_codes FROM postal_codes;
"

echo ""
echo "5. Agder region coverage:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT COUNT(*) as agder_postal_codes
FROM postal_codes
WHERE postal_code LIKE '4%';
"

echo ""
echo "6. Sample postal codes:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT postal_code, postal_name, municipality_number
FROM postal_codes
WHERE postal_code LIKE '4%'
ORDER BY postal_code
LIMIT 5;
"

echo ""
echo "=========================================="
echo "[OK] Postal code data loaded successfully!"
echo "=========================================="
