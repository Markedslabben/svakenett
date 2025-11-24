#!/usr/bin/env python3
"""
Load NVE infrastructure data from GeoJSON to PostgreSQL
Uses simple JSON + PostGIS to avoid pyproj issues
"""

import json
import psycopg2
import sys

# Configuration
DATA_PATH = "/mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure"
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'svakenett',
    'user': 'postgres'
}

def load_geojson_to_postgis(geojson_file, table_name):
    """Load GeoJSON features into PostGIS table"""
    print(f"\nLoading {geojson_file} into {table_name}...")

    # Read GeoJSON
    with open(f"{DATA_PATH}/{geojson_file}", 'r') as f:
        data = json.load(f)

    features = data['features']
    print(f"  ✓ Read {len(features)} features")

    # Connect to database
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    try:
        # Drop and recreate table
        cur.execute(f"DROP TABLE IF EXISTS {table_name}")

        # Create table based on first feature
        if len(features) == 0:
            print("  ✗ No features to load")
            return 0

        first_props = features[0]['properties']

        # Build CREATE TABLE statement
        columns = []
        for key, value in first_props.items():
            if isinstance(value, int):
                col_type = "INTEGER"
            elif isinstance(value, float):
                col_type = "REAL"
            else:
                col_type = "TEXT"

            # Clean column name
            clean_key = key.lower().replace(' ', '_')
            columns.append(f"{clean_key} {col_type}")

        # Check if geometry has Z dimension
        first_geom = features[0]['geometry']
        has_z = False
        if first_geom['type'] in ['Point', 'MultiPoint']:
            coords = first_geom['coordinates']
            if first_geom['type'] == 'Point':
                has_z = len(coords) > 2
            else:
                has_z = len(coords[0]) > 2 if len(coords) > 0 else False
        elif first_geom['type'] in ['LineString', 'MultiLineString']:
            coords = first_geom['coordinates']
            if first_geom['type'] == 'LineString':
                has_z = len(coords[0]) > 2 if len(coords) > 0 else False
            else:
                has_z = len(coords[0][0]) > 2 if len(coords) > 0 and len(coords[0]) > 0 else False

        geom_type = "GEOMETRYZ" if has_z else "GEOMETRY"
        print(f"  → Geometry type: {geom_type}")

        create_sql = f"""
        CREATE TABLE {table_name} (
            id SERIAL PRIMARY KEY,
            {', '.join(columns)},
            geometry GEOMETRY({geom_type}, 4326)
        )
        """

        cur.execute(create_sql)
        print(f"  ✓ Created table {table_name}")

        # Insert features
        inserted = 0
        for feature in features:
            props = feature['properties']
            geom = feature['geometry']

            # Build INSERT statement
            col_names = [k.lower().replace(' ', '_') for k in props.keys()]
            col_values = [props[k] for k in props.keys()]

            placeholders = ', '.join(['%s'] * len(col_values))
            columns_str = ', '.join(col_names)

            insert_sql = f"""
            INSERT INTO {table_name} ({columns_str}, geometry)
            VALUES ({placeholders}, ST_GeomFromGeoJSON(%s))
            """

            cur.execute(insert_sql, col_values + [json.dumps(geom)])
            inserted += 1

            if inserted % 1000 == 0:
                print(f"  → Inserted {inserted}/{len(features)}...")

        # Commit
        conn.commit()
        print(f"  ✓ Inserted {inserted} features")

        # Create spatial index
        cur.execute(f"CREATE INDEX idx_{table_name}_geom ON {table_name} USING GIST(geometry)")
        conn.commit()
        print(f"  ✓ Created spatial index")

        return inserted

    except Exception as e:
        conn.rollback()
        print(f"  ✗ Error: {e}")
        return 0
    finally:
        cur.close()
        conn.close()

def main():
    print("=" * 60)
    print("Loading Complete NVE Infrastructure Data (Simple Method)")
    print("=" * 60)

    # Load power lines
    power_lines_count = load_geojson_to_postgis(
        "kraftlinje_complete.geojson",
        "power_lines_new"
    )

    # Load transformers
    transformers_count = load_geojson_to_postgis(
        "transformers_complete.geojson",
        "transformers_new"
    )

    if power_lines_count > 0 and transformers_count > 0:
        print("\n" + "=" * 60)
        print("✓ Successfully loaded:")
        print(f"  - {power_lines_count} power lines")
        print(f"  - {transformers_count} transformers")
        print("=" * 60)
        print("\nNext: Rename tables and recalculate metrics")
        return 0
    else:
        print("\n✗ Failed to load data")
        return 1

if __name__ == "__main__":
    sys.exit(main())
