#!/usr/bin/env python3
"""
Load complete NVE infrastructure data from File Geodatabase to PostgreSQL
Replaces partial data with full 9,715 power lines dataset
"""

import geopandas as gpd
from sqlalchemy import create_engine
import sys

# Configuration
DATA_PATH = "/mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure"
DB_URL = "postgresql://postgres@localhost:5432/svakenett"

def load_layer(geojson_file, table_name):
    """Load a GeoJSON file to PostgreSQL"""
    print(f"\nLoading {geojson_file}...")

    try:
        # Read from GeoJSON (already in EPSG:4326)
        gdf = gpd.read_file(f"{DATA_PATH}/{geojson_file}")
        print(f"  ✓ Read {len(gdf)} features from GeoJSON")

        # Create database engine
        engine = create_engine(DB_URL)

        # Write to PostgreSQL
        print(f"  → Writing to PostgreSQL table '{table_name}'...")
        gdf.to_postgis(
            name=table_name,
            con=engine,
            if_exists='replace',
            index=True,
            index_label='id'
        )

        print(f"  ✓ Loaded {len(gdf)} features into {table_name}")
        return len(gdf)

    except Exception as e:
        print(f"  ✗ Error loading {layer_name}: {e}")
        return 0

def main():
    print("=" * 50)
    print("Loading Complete NVE Infrastructure Data")
    print("=" * 50)

    # Load power lines
    kraftlinje_count = load_layer("kraftlinje_complete.geojson", "power_lines_new")

    # Load transformers
    transformer_count = load_layer("transformers_complete.geojson", "transformers_new")

    if kraftlinje_count > 0 and transformer_count > 0:
        print("\n" + "=" * 50)
        print(f"✓ Successfully loaded:")
        print(f"  - {kraftlinje_count} power lines")
        print(f"  - {transformer_count} transformers")
        print("=" * 50)

        print("\nNext: Run SQL to rename tables and add indexes")
        return 0
    else:
        print("\n✗ Failed to load data")
        return 1

if __name__ == "__main__":
    sys.exit(main())
