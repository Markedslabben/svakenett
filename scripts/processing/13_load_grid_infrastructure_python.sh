#!/bin/bash
# Load NVE grid infrastructure GeoJSON data into PostGIS using Python
# Simple, reliable approach that works without ogr2ogr

set -e

echo "=========================================="
echo "Loading Grid Infrastructure to PostGIS"
echo "=========================================="

# Check data files exist
DATA_DIR="data/nve_infrastructure"
for file in power_lines.geojson power_poles.geojson cables.geojson transformers.geojson; do
    if [ ! -f "$DATA_DIR/$file" ]; then
        echo "✗ Error: $DATA_DIR/$file not found"
        exit 1
    fi
done

echo "✓ All GeoJSON files found"
echo ""

# Python script to load GeoJSON into PostGIS
python3 << 'EOF'
import json
import sys

def load_power_lines():
    """Load power lines from GeoJSON"""
    print("1. Loading power_lines...")

    with open('data/nve_infrastructure/power_lines.geojson', 'r') as f:
        data = json.load(f)

    features = data.get('features', [])
    print(f"   Found {len(features)} power line features")

    sql_statements = []
    for feature in features:
        props = feature['properties']
        geom = feature['geometry']

        # Extract fields (handle None values)
        voltage_kv = props.get('spenning_kV') or 'NULL'
        owner_orgnr = props.get('eierOrgnr', '')
        owner_name = props.get('eier', '').replace("'", "''")
        year_built = props.get('driftsattaar') or 'NULL'
        line_type = props.get('objektType', '').replace("'", "''")

        # Calculate line length from geometry
        geom_json = json.dumps(geom).replace("'", "''")

        sql = f"""
INSERT INTO power_lines (geometry, voltage_kv, owner_orgnr, owner_name, year_built, line_type, line_length_m)
VALUES (
    ST_Force2D(ST_GeomFromGeoJSON('{geom_json}')),
    {voltage_kv},
    '{owner_orgnr}',
    '{owner_name}',
    {year_built},
    '{line_type}',
    ST_Length(ST_Force2D(ST_GeomFromGeoJSON('{geom_json}'))::geography)
);"""
        sql_statements.append(sql)

    # Write to file
    with open('/tmp/load_power_lines.sql', 'w') as f:
        f.write('\n'.join(sql_statements))

    print(f"   ✓ Generated SQL for {len(sql_statements)} power lines")
    return len(sql_statements)

def load_power_poles():
    """Load power poles from GeoJSON"""
    print("2. Loading power_poles...")

    with open('data/nve_infrastructure/power_poles.geojson', 'r') as f:
        data = json.load(f)

    features = data.get('features', [])
    print(f"   Found {len(features)} power pole features")

    sql_statements = []
    for feature in features:
        props = feature['properties']
        geom = feature['geometry']

        owner_orgnr = props.get('eierOrgnr', '')
        owner_name = props.get('eier', '').replace("'", "''")
        year_built = props.get('driftsattaar', '').replace("'", "''") if props.get('driftsattaar') else 'NULL'
        pole_height_m = props.get('mastehoyde_m') or 'NULL'
        pole_type = props.get('objektType', '').replace("'", "''")

        geom_json = json.dumps(geom).replace("'", "''")

        sql = f"""
INSERT INTO power_poles (geometry, owner_orgnr, owner_name, year_built, height_m, pole_type)
VALUES (
    ST_Force2D(ST_GeomFromGeoJSON('{geom_json}')),
    '{owner_orgnr}',
    '{owner_name}',
    {year_built},
    {pole_height_m},
    '{pole_type}'
);"""
        sql_statements.append(sql)

    with open('/tmp/load_power_poles.sql', 'w') as f:
        f.write('\n'.join(sql_statements))

    print(f"   ✓ Generated SQL for {len(sql_statements)} power poles")
    return len(sql_statements)

def load_cables():
    """Load cables from GeoJSON"""
    print("3. Loading cables...")

    with open('data/nve_infrastructure/cables.geojson', 'r') as f:
        data = json.load(f)

    features = data.get('features', [])
    print(f"   Found {len(features)} cable features")

    sql_statements = []
    for feature in features:
        props = feature['properties']
        geom = feature['geometry']

        owner_orgnr = props.get('eierOrgnr', '')
        owner_name = props.get('eier', '').replace("'", "''")
        cable_type = props.get('objektType', '').replace("'", "''")
        year_built = props.get('driftsattaar') or 'NULL'

        geom_json = json.dumps(geom).replace("'", "''")

        sql = f"""
INSERT INTO cables (geometry, cable_type, owner_orgnr, owner_name, year_built, cable_length_m)
VALUES (
    ST_Force2D(ST_GeomFromGeoJSON('{geom_json}')),
    '{cable_type}',
    '{owner_orgnr}',
    '{owner_name}',
    {year_built},
    ST_Length(ST_Force2D(ST_GeomFromGeoJSON('{geom_json}'))::geography)
);"""
        sql_statements.append(sql)

    with open('/tmp/load_cables.sql', 'w') as f:
        f.write('\n'.join(sql_statements))

    print(f"   ✓ Generated SQL for {len(sql_statements)} cables")
    return len(sql_statements)

def load_transformers():
    """Load transformers from GeoJSON"""
    print("4. Loading transformers...")

    with open('data/nve_infrastructure/transformers.geojson', 'r') as f:
        data = json.load(f)

    features = data.get('features', [])
    print(f"   Found {len(features)} transformer features")

    sql_statements = []
    for feature in features:
        props = feature['properties']
        geom = feature['geometry']

        owner_orgnr = props.get('eierOrgnr', '') or ''
        owner_name = (props.get('eier') or '').replace("'", "''")
        transformer_type = (props.get('objektType') or '').replace("'", "''")
        year_built = props.get('driftsattaar') or 'NULL'

        geom_json = json.dumps(geom).replace("'", "''")

        sql = f"""
INSERT INTO transformers (geometry, station_type, owner_orgnr, owner_name, year_built)
VALUES (
    ST_Force2D(ST_GeomFromGeoJSON('{geom_json}')),
    '{transformer_type}',
    '{owner_orgnr}',
    '{owner_name}',
    {year_built}
);"""
        sql_statements.append(sql)

    with open('/tmp/load_transformers.sql', 'w') as f:
        f.write('\n'.join(sql_statements))

    print(f"   ✓ Generated SQL for {len(sql_statements)} transformers")
    return len(sql_statements)

# Load all layers
print("")
try:
    lines_count = load_power_lines()
    poles_count = load_power_poles()
    cables_count = load_cables()
    transformers_count = load_transformers()

    print("")
    print(f"✓ SQL generation complete:")
    print(f"  - {lines_count} power lines")
    print(f"  - {poles_count} power poles")
    print(f"  - {cables_count} cables")
    print(f"  - {transformers_count} transformers")

except Exception as e:
    print(f"✗ Error: {e}", file=sys.stderr)
    sys.exit(1)

EOF

# Load generated SQL into PostgreSQL
echo ""
echo "Loading data into PostgreSQL..."

echo "  - Power lines..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/load_power_lines.sql > /dev/null 2>&1
echo "  ✓ Power lines loaded"

echo "  - Power poles..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/load_power_poles.sql > /dev/null 2>&1
echo "  ✓ Power poles loaded"

echo "  - Cables..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/load_cables.sql > /dev/null 2>&1
echo "  ✓ Cables loaded"

echo "  - Transformers..."
docker exec -i svakenett-postgis psql -U postgres -d svakenett < /tmp/load_transformers.sql > /dev/null 2>&1
echo "  ✓ Transformers loaded"

# Verify
echo ""
echo "Verifying data load..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    'power_lines' as table_name, COUNT(*) as row_count FROM power_lines
UNION ALL
SELECT 'power_poles', COUNT(*) FROM power_poles
UNION ALL
SELECT 'cables', COUNT(*) FROM cables
UNION ALL
SELECT 'transformers', COUNT(*) FROM transformers;
"

echo ""
echo "=========================================="
echo "[OK] Grid infrastructure data loaded!"
echo "=========================================="
echo ""
echo "Next step: Run ./scripts/14_calculate_metrics.sh"
