#!/usr/bin/env python3
"""
Load NVE Power Poles (Mast) into PostgreSQL+PostGIS

This script loads power pole/tower locations from NVE's GDB format.
Power poles are used for grid density analysis.

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
CURRENT_YEAR = 2025

COLUMN_MAPPING = {
    'objektType': 'objekt_type',
    'nveNettnivaa': 'nve_nett_nivaa',
    'nettnivaa': 'nett_nivaa_navn',
    'eier': 'eier',
    'eierOrgnr': 'eier_org_nr',
    'driftsattaar': 'driftsatt_aar',
    'mastehoyde_m': 'maste_hoyde_m',
    'lokalID': 'lokal_id',
    'nveOpprettetDato': 'nve_opprettet_dato',
    'kildeEndretDato': 'kilde_endret_dato'
}

FINAL_COLUMNS = [
    'geometry', 'objekt_type', 'nve_nett_nivaa', 'nett_nivaa_navn',
    'eier', 'eier_org_nr', 'driftsatt_aar', 'alder_aar',
    'maste_hoyde_m', 'lokal_id', 'nve_opprettet_dato', 'kilde_endret_dato'
]

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main execution function."""
    print("=" * 70)
    print("NVE Power Poles Data Loader")
    print("=" * 70)
    print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Validate GDB exists
    if not os.path.exists(GDB_PATH):
        print(f"❌ ERROR: GDB file not found at {GDB_PATH}")
        sys.exit(1)
    print(f"✓ GDB file found: {GDB_PATH}")

    # Load Mast layer
    print(f"\n[Power Poles] Loading layer 'Mast'...")
    gdf = gpd.read_file(GDB_PATH, layer='Mast')
    print(f"  → Loaded {len(gdf):,} features")
    print(f"  → Original CRS: {gdf.crs}")

    # Transform CRS to WGS84
    if gdf.crs != 'EPSG:4326':
        gdf = gdf.to_crs(epsg=4326)
        print(f"  → Transformed to EPSG:4326 (WGS84)")

    # Calculate infrastructure age
    gdf['alder_aar'] = CURRENT_YEAR - gdf['driftsattaar']
    print(f"  → Calculated infrastructure age")

    # Rename columns
    gdf = gdf.rename(columns=COLUMN_MAPPING)

    # Select columns
    available_cols = [col for col in FINAL_COLUMNS if col in gdf.columns]
    gdf = gdf[available_cols]

    # Data quality check
    print(f"\n[Quality Check]")
    print(f"  Distribution level poles (nveNettnivaa=3): {len(gdf[gdf['nve_nett_nivaa']==3]):,} ({100*len(gdf[gdf['nve_nett_nivaa']==3])/len(gdf):.1f}%)")
    print(f"  Average age: {gdf['alder_aar'].mean():.1f} years")
    print(f"  Age range: {gdf['driftsatt_aar'].min()} - {gdf['driftsatt_aar'].max()}")

    # Load to PostgreSQL
    print(f"\n[Database] Loading to PostgreSQL table 'nve_power_poles'...")
    engine = create_engine(DB_URL)

    gdf.to_postgis(
        name='nve_power_poles',
        con=engine,
        if_exists='replace',
        index=False,
        chunksize=5000
    )

    print(f"  ✓ {len(gdf):,} records loaded")
    engine.dispose()

    # Summary
    print("\n" + "=" * 70)
    print("✓ POWER POLES LOADING COMPLETE")
    print("=" * 70)
    print(f"  Total poles: {len(gdf):,}")
    print(f"  End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    print("Next steps:")
    print("  1. Load transformers: python3 scripts/load_nve_transformers.py")
    print("  2. Validate data: psql $DATABASE_URL -f scripts/validate_nve_load.sql")


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
