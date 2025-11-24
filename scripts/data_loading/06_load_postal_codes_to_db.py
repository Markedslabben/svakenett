#!/usr/bin/env python3
"""
Load postal code geometries from JSON into PostgreSQL
"""

import json
import sys
import subprocess

JSON_FILE = "data/postal_codes/postal-codes.json"

print("=" * 70)
print("Loading Postal Code Geometries into PostgreSQL")
print("=" * 70)

print(f"\n1. Loading {JSON_FILE}...")
with open(JSON_FILE, 'r', encoding='utf-8') as f:
    data = json.load(f)

print(f"   Total postal codes: {len(data)}")

# Filter postal codes with valid geometries
postal_codes_with_geom = []
for code, entry in data.items():
    if entry.get('geojson'):
        postal_codes_with_geom.append({
            'code': code,
            'name': entry.get('poststed', ''),
            'municipality_code': entry.get('kommunenummer', ''),
            'municipality_name': entry.get('kommune', ''),
            'county': entry.get('fylke', ''),
            'county_code': entry.get('fylkesnummer', ''),
            'category': entry.get('kategori', ''),
            'geojson': entry.get('geojson')
        })

print(f"\n2. Found {len(postal_codes_with_geom)} postal codes with geometries")

# Clear existing data
print("\n3. Clearing existing postal_codes data...")
result = subprocess.run([
    'docker', 'exec', 'svakenett-postgis',
    'psql', '-U', 'postgres', '-d', 'svakenett',
    '-c', 'DELETE FROM postal_codes;'
], capture_output=True, text=True)

if result.returncode != 0:
    print(f"   Error: {result.stderr}")
    sys.exit(1)

print("   Cleared existing data")

# Generate SQL INSERT statements
print("\n4. Generating INSERT statements...")
sql_statements = []

for pc in postal_codes_with_geom:
    # Escape single quotes in text fields
    name = pc['name'].replace("'", "''")
    municipality = pc['municipality_name'].replace("'", "''")
    county = pc['county'].replace("'", "''")

    # Convert GeoJSON to PostGIS geometry
    # GeoJSON is already in WGS84 (EPSG:4326)
    geojson_str = json.dumps(pc['geojson']).replace("'", "''")

    sql = f"""INSERT INTO postal_codes (
        postal_code,
        postal_name,
        municipality_code,
        municipality_name,
        county_name,
        county_code,
        category,
        boundary_polygon
    ) VALUES (
        '{pc['code']}',
        '{name}',
        '{pc['municipality_code']}',
        '{municipality}',
        '{county}',
        '{pc['county_code']}',
        '{pc['category']}',
        ST_GeomFromGeoJSON('{geojson_str}')
    );"""

    sql_statements.append(sql)

print(f"   Generated {len(sql_statements)} INSERT statements")

# Execute SQL in batches
print("\n5. Loading data to database...")
batch_size = 100
total_batches = (len(sql_statements) + batch_size - 1) // batch_size

for i in range(0, len(sql_statements), batch_size):
    batch = sql_statements[i:i + batch_size]
    batch_sql = '\n'.join(batch)

    batch_num = (i // batch_size) + 1
    print(f"   Processing batch {batch_num}/{total_batches}...", end='\r')

    result = subprocess.run([
        'docker', 'exec', '-i', 'svakenett-postgis',
        'psql', '-U', 'postgres', '-d', 'svakenett'
    ], input=batch_sql, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"\n   Error in batch {batch_num}: {result.stderr}")
        sys.exit(1)

print(f"\n   Loaded {len(sql_statements)} postal codes successfully!")

# Verify
print("\n6. Verifying data...")
result = subprocess.run([
    'docker', 'exec', 'svakenett-postgis',
    'psql', '-U', 'postgres', '-d', 'svakenett', '-t', '-c',
    'SELECT COUNT(*) FROM postal_codes;'
], capture_output=True, text=True)

count = result.stdout.strip()
print(f"   Total postal codes in database: {count}")

# Show Agder region coverage
result = subprocess.run([
    'docker', 'exec', 'svakenett-postgis',
    'psql', '-U', 'postgres', '-d', 'svakenett', '-t', '-c',
    "SELECT COUNT(*) FROM postal_codes WHERE postal_code LIKE '4%';"
], capture_output=True, text=True)

agder_count = result.stdout.strip()
print(f"   Agder region (4xxx) postal codes: {agder_count}")

# Show sample postal codes
print("\n7. Sample postal codes from database:")
result = subprocess.run([
    'docker', 'exec', 'svakenett-postgis',
    'psql', '-U', 'postgres', '-d', 'svakenett', '-c',
    """SELECT postal_code, postal_name, municipality_name, county_name
       FROM postal_codes
       WHERE postal_code LIKE '4%'
       ORDER BY postal_code
       LIMIT 5;"""
], capture_output=True, text=True)

print(result.stdout)

print("\n" + "=" * 70)
print("[OK] Postal code data loaded successfully!")
print("=" * 70)
