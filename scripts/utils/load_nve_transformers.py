#!/usr/bin/env python3
"""
Load NVE Transformer Stations into PostgreSQL+PostGIS

This script loads transformer station locations from NVE's GDB format.
Transformers are used to calculate distance from power source.

Author: Klaus
Date: 2025-01-22
"""

import geopandas as gpd
from sqlalchemy import create_engine
import os
import sys
from datetime import datetime

# ============================================================================
# CONFIGURATION
# ============================================================================

DB_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/svakenett')
GDB_PATH = '/mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure/NVEData.gdb'

COLUMN_MAPPING = {
    'objektType': 'objekt_type',
    'nveNettnivaa': 'nve_nett_nivaa',
    'nettnivaa': 'nett_nivaa_navn',
    'spenning_kV': 'spenning_kv',
    'eier': 'eier',
    'eierOrgnr': 'eier_org_nr',
    'navn': 'navn',
    'driftsattaar': 'driftsatt_aar',
    'lokalID': 'lokal_id',
    'nveOpprettetDato': 'nve_opprettet_dato',
    'kildeEndretDato': 'kilde_endret_dato'
}

FINAL_COLUMNS = [
    'geometry', 'objekt_type', 'nve_nett_nivaa', 'nett_nivaa_navn',
    'spenning_kv', 'eier', 'eier_org_nr', 'navn', 'driftsatt_aar',
    'lokal_id', 'nve_opprettet_dato', 'kilde_endret_dato'
]

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main execution function."""
    print("=" * 70)
    print("NVE Transformer Stations Data Loader")
    print("=" * 70)
    print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Validate GDB exists
    if not os.path.exists(GDB_PATH):
        print(f"❌ ERROR: GDB file not found at {GDB_PATH}")
        sys.exit(1)
    print(f"✓ GDB file found: {GDB_PATH}")

    # Load Transformatorstasjon layer
    print(f"\n[Transformers] Loading layer 'Transformatorstasjon'...")
    gdf = gpd.read_file(GDB_PATH, layer='Transformatorstasjon')
    print(f"  → Loaded {len(gdf):,} features")
    print(f"  → Original CRS: {gdf.crs}")

    # Transform CRS to WGS84
    if gdf.crs != 'EPSG:4326':
        gdf = gdf.to_crs(epsg=4326)
        print(f"  → Transformed to EPSG:4326 (WGS84)")

    # Rename columns
    gdf = gdf.rename(columns=COLUMN_MAPPING)

    # Select columns
    available_cols = [col for col in FINAL_COLUMNS if col in gdf.columns]
    gdf = gdf[available_cols]

    # Data quality check
    print(f"\n[Quality Check]")
    print(f"  Regional transformers (nveNettnivaa=2): {len(gdf[gdf['nve_nett_nivaa']==2]):,}")
    print(f"  Level distribution:")
    for level, count in gdf['nve_nett_nivaa'].value_counts().sort_index().items():
        print(f"    Level {level}: {count} stations")

    # Load to PostgreSQL
    print(f"\n[Database] Loading to PostgreSQL table 'nve_transformers'...")
    engine = create_engine(DB_URL)

    gdf.to_postgis(
        name='nve_transformers',
        con=engine,
        if_exists='replace',
        index=False,
        chunksize=100
    )

    print(f"  ✓ {len(gdf):,} records loaded")
    engine.dispose()

    # Summary
    print("\n" + "=" * 70)
    print("✓ TRANSFORMER STATIONS LOADING COMPLETE")
    print("=" * 70)
    print(f"  Total transformers: {len(gdf):,}")
    print(f"  End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    print("Next steps:")
    print("  1. Validate all data: psql $DATABASE_URL -f scripts/validate_nve_load.sql")
    print("  2. Calculate cabin distances: psql $DATABASE_URL -f scripts/calculate_cabin_grid_distances.sql")


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
