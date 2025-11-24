#!/usr/bin/env python3
"""
Export cabins to GeoPackage for QGIS visualization
"""

import geopandas as gpd
from sqlalchemy import create_engine
from pathlib import Path

# Database connection
DATABASE_URL = 'postgresql://postgres:weakgrid2024@localhost:5432/svakenett'

# Output path (shared folder)
OUTPUT_PATH = Path('/mnt/c/Users/klaus/klauspython/qgis/svakenett/agder_cabins.gpkg')

def main():
    print("Connecting to database...")
    engine = create_engine(DATABASE_URL)

    print("Loading cabins...")
    cabins_gdf = gpd.read_postgis(
        'SELECT * FROM cabins',
        engine,
        geom_col='geometry'
    )

    print(f"✓ Loaded {len(cabins_gdf):,} cabins")

    # Ensure output directory exists
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    print(f"\nExporting to: {OUTPUT_PATH}")
    cabins_gdf.to_file(OUTPUT_PATH, driver='GPKG', layer='cabins')

    print(f"✓ Export complete!")
    print(f"\n{'='*60}")
    print("QGIS Instructions (on remote server):")
    print(f"{'='*60}")
    print(f"1. Open QGIS")
    print(f"2. Layer → Add Vector Layer (Ctrl+Shift+V)")
    print(f"3. Browse to: {OUTPUT_PATH}")
    print(f"4. Select 'cabins' layer")
    print(f"5. Click 'Add'")
    print(f"\nThe file contains {len(cabins_gdf):,} cabin points in WGS84 (EPSG:4326)")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
