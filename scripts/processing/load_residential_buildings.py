#!/usr/bin/env python3
"""
Load residential buildings (boliger) from Matrikkelen to PostgreSQL
Building types: 111 (Enebolig), 112 (Tomannsbolig), 113 (Rekkehus), 121 (Våningshus)
"""

import fiona
import psycopg2
import json
from collections import defaultdict

GDB_PATH = "/mnt/c/users/klaus/klauspython/qgis/svakenett/matrikkelen_data/Basisdata_42_Agder_25833_MatrikkelenBygning_FGDB.gdb"
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'svakenett',
    'user': 'postgres'
}

# Residential building types
RESIDENTIAL_TYPES = {
    111: "Enebolig",
    112: "Tomannsbolig",
    113: "Rekkehus",
    121: "Våningshus"
}

print("=" * 70)
print("Loading Residential Buildings (Boliger) from Matrikkelen")
print("=" * 70)

# Connect to database
conn = psycopg2.connect(**DB_CONFIG)
cur = conn.cursor()

try:
    # Create residential_buildings table
    print("\n1. Creating residential_buildings table...")
    cur.execute("DROP TABLE IF EXISTS residential_buildings CASCADE")

    cur.execute("""
        CREATE TABLE residential_buildings (
            id SERIAL PRIMARY KEY,
            bygningsnummer INTEGER,
            bygningstype INTEGER,
            building_type_name TEXT,
            kommunenummer TEXT,
            kommunenavn TEXT,
            bygningsstatus TEXT,
            opprinnelse TEXT,
            naringsgruppe TEXT,
            oppdateringsdato TIMESTAMP,
            geometry GEOMETRY(POINT, 4326),

            -- Grid metrics (to be calculated later)
            distance_to_line_m REAL,
            grid_density_lines_1km INTEGER,
            voltage_level_kv REAL,
            grid_age_years REAL,
            distance_to_transformer_m REAL,
            weak_grid_score REAL
        )
    """)

    print("  ✓ Table created")

    # Read and filter residential buildings
    print("\n2. Reading buildings from geodatabase...")

    residential_count = defaultdict(int)
    inserted = 0
    skipped = 0

    with fiona.open(GDB_PATH, layer='bygning') as src:
        print(f"  Total buildings in source: {len(src):,}")

        # We need to transform from EPSG:25833 to EPSG:4326
        from_crs = src.crs
        print(f"  Source CRS: {from_crs}")

        for i, feature in enumerate(src):
            if i % 10000 == 0 and i > 0:
                print(f"  Processed {i:,} features ({inserted:,} residential)...")

            props = feature['properties']
            bygningstype = props.get('bygningstype')

            # Only process residential buildings
            if bygningstype not in RESIDENTIAL_TYPES:
                skipped += 1
                continue

            residential_count[bygningstype] += 1

            # Get geometry
            geom = feature['geometry']
            coords = geom['coordinates']

            # Transform from EPSG:25833 to EPSG:4326
            # For now, store original coords and transform in PostGIS
            geom_wkt = f"SRID=25833;POINT({coords[0]} {coords[1]})"

            # Insert into database
            cur.execute("""
                INSERT INTO residential_buildings (
                    bygningsnummer, bygningstype, building_type_name,
                    kommunenummer, kommunenavn, bygningsstatus,
                    opprinnelse, naringsgruppe, oppdateringsdato,
                    geometry
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    ST_Transform(ST_GeomFromText(%s), 4326)
                )
            """, (
                props.get('bygningsnummer'),
                bygningstype,
                RESIDENTIAL_TYPES[bygningstype],
                props.get('kommunenummer'),
                props.get('kommunenavn'),
                props.get('bygningsstatus'),
                props.get('opprinnelse'),
                props.get('naringsgruppe'),
                props.get('oppdateringsdato'),
                geom_wkt
            ))

            inserted += 1

            # Commit every 5000 rows
            if inserted % 5000 == 0:
                conn.commit()

    # Final commit
    conn.commit()

    print(f"\n  ✓ Processed all {i+1:,} buildings")
    print(f"  ✓ Inserted {inserted:,} residential buildings")
    print(f"  ✓ Skipped {skipped:,} non-residential buildings")

    # Show breakdown by type
    print("\n3. Residential buildings by type:")
    for bygtype, count in sorted(residential_count.items()):
        name = RESIDENTIAL_TYPES[bygtype]
        pct = 100.0 * count / inserted
        print(f"  {bygtype} - {name:20s}: {count:7,} ({pct:5.1f}%)")

    # Create indexes
    print("\n4. Creating indexes...")
    cur.execute("CREATE INDEX idx_residential_geom ON residential_buildings USING GIST(geometry)")
    cur.execute("CREATE INDEX idx_residential_type ON residential_buildings(bygningstype)")
    cur.execute("CREATE INDEX idx_residential_kommune ON residential_buildings(kommunenummer)")
    conn.commit()
    print("  ✓ Indexes created")

    # Verify
    print("\n5. Verification:")
    cur.execute("SELECT COUNT(*) FROM residential_buildings")
    total = cur.fetchone()[0]
    print(f"  Total residential buildings in database: {total:,}")

    cur.execute("""
        SELECT bygningstype, building_type_name, COUNT(*)
        FROM residential_buildings
        GROUP BY bygningstype, building_type_name
        ORDER BY bygningstype
    """)

    print("\n  Breakdown:")
    for row in cur.fetchall():
        print(f"    {row[0]} - {row[1]}: {row[2]:,}")

    print("\n" + "=" * 70)
    print("✓ Residential Buildings Loaded Successfully")
    print("=" * 70)
    print("\nNext step: Calculate grid metrics for residential buildings")

except Exception as e:
    conn.rollback()
    print(f"\n✗ Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    cur.close()
    conn.close()
