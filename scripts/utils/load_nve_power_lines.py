#!/usr/bin/env python3
"""
Load NVE Power Lines and Sea Cables into PostgreSQL+PostGIS

This script loads power transmission infrastructure from NVE's GDB format:
- Kraftlinje (overhead power lines)
- Sjokabel (submarine power cables)

Both are combined into a single nve_power_lines table for unified analysis.

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

# Database connection
DB_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/svakenett')

# NVE data path
GDB_PATH = '/mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure/NVEData.gdb'

# Current year for age calculation
CURRENT_YEAR = 2025

# Column mapping from NVE schema to our schema
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
    'kildeEndretDato': 'kilde_endret_dato',
    'dataUttaksdato': 'data_uttaks_dato'
}

# Columns to keep in final table
FINAL_COLUMNS = [
    'geometry', 'objekt_type', 'nve_nett_nivaa', 'nett_nivaa_navn',
    'spenning_kv', 'eier', 'eier_org_nr', 'navn', 'driftsatt_aar',
    'alder_aar', 'lengde_m', 'lokal_id', 'nve_opprettet_dato',
    'kilde_endret_dato', 'data_uttaks_dato'
]

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def validate_gdb_exists():
    """Check if GDB file exists before attempting to load."""
    if not os.path.exists(GDB_PATH):
        print(f"❌ ERROR: GDB file not found at {GDB_PATH}")
        print(f"   Please verify the data path is correct.")
        sys.exit(1)
    print(f"✓ GDB file found: {GDB_PATH}")


def load_and_transform_layer(layer_name, layer_type):
    """
    Load a layer from GDB, transform CRS, and prepare for database insertion.

    Args:
        layer_name (str): Name of layer in GDB (e.g., 'Kraftlinje')
        layer_type (str): Human-readable type for logging (e.g., 'Power Lines')

    Returns:
        GeoDataFrame: Processed geodataframe ready for PostGIS
    """
    print(f"\n[{layer_type}] Loading layer '{layer_name}'...")

    # Load from GDB
    gdf = gpd.read_file(GDB_PATH, layer=layer_name)
    print(f"  → Loaded {len(gdf):,} features")
    print(f"  → Original CRS: {gdf.crs}")

    # Transform CRS: EPSG:32633 (UTM Zone 33N) → EPSG:4326 (WGS84)
    if gdf.crs != 'EPSG:4326':
        gdf = gdf.to_crs(epsg=4326)
        print(f"  → Transformed to EPSG:4326 (WGS84)")

    # Calculate infrastructure age
    gdf['alder_aar'] = CURRENT_YEAR - gdf['driftsattaar']
    print(f"  → Calculated infrastructure age (oldest: {gdf['driftsattaar'].min()}, "
          f"newest: {gdf['driftsattaar'].max()})")

    # Calculate line length in meters (use UTM for accurate measurement)
    gdf_utm = gdf.to_crs(epsg=32633)  # Temporarily back to UTM
    gdf['lengde_m'] = gdf_utm.geometry.length
    print(f"  → Calculated line lengths (total: {gdf['lengde_m'].sum()/1000:.1f} km)")

    # Rename columns to match our schema
    gdf = gdf.rename(columns=COLUMN_MAPPING)

    # Select only needed columns (handle missing columns gracefully)
    available_cols = [col for col in FINAL_COLUMNS if col in gdf.columns]
    gdf = gdf[available_cols]

    # Data quality checks
    null_counts = gdf.isnull().sum()
    critical_nulls = null_counts[null_counts > 0]
    if len(critical_nulls) > 0:
        print(f"  ⚠ Null values detected:")
        for col, count in critical_nulls.items():
            print(f"    - {col}: {count} nulls ({100*count/len(gdf):.1f}%)")

    return gdf


def load_to_postgis(gdf, table_name, if_exists='replace'):
    """
    Load GeoDataFrame to PostgreSQL+PostGIS.

    Args:
        gdf (GeoDataFrame): Data to load
        table_name (str): Target table name
        if_exists (str): 'replace' or 'append'
    """
    print(f"\n[Database] Loading to PostgreSQL table '{table_name}'...")

    # Create database engine
    engine = create_engine(DB_URL)

    # Load to database
    gdf.to_postgis(
        name=table_name,
        con=engine,
        if_exists=if_exists,
        index=False,
        chunksize=1000
    )

    print(f"  ✓ {len(gdf):,} records loaded to '{table_name}'")

    # Dispose engine
    engine.dispose()


# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main execution function."""
    print("=" * 70)
    print("NVE Power Lines Data Loader")
    print("=" * 70)
    print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Step 1: Validate GDB file exists
    validate_gdb_exists()

    # Step 2: Load Kraftlinje (overhead power lines)
    gdf_kraftlinje = load_and_transform_layer('Kraftlinje', 'Power Lines')

    # Step 3: Load Sjokabel (submarine power cables)
    gdf_sjokabel = load_and_transform_layer('Sjokabel', 'Sea Cables')

    # Step 4: Load Kraftlinje to database (replace existing table)
    load_to_postgis(gdf_kraftlinje, 'nve_power_lines', if_exists='replace')

    # Step 5: Append Sjokabel to same table
    load_to_postgis(gdf_sjokabel, 'nve_power_lines', if_exists='append')

    # Summary
    total_lines = len(gdf_kraftlinje) + len(gdf_sjokabel)
    print("\n" + "=" * 70)
    print("✓ POWER LINES LOADING COMPLETE")
    print("=" * 70)
    print(f"  Total records: {total_lines:,}")
    print(f"    - Kraftlinje (overhead): {len(gdf_kraftlinje):,}")
    print(f"    - Sjokabel (sea cables): {len(gdf_sjokabel):,}")
    print(f"  End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Next steps
    print("Next steps:")
    print("  1. Load power poles: python3 scripts/load_nve_power_poles.py")
    print("  2. Load transformers: python3 scripts/load_nve_transformers.py")
    print("  3. Validate data: psql $DATABASE_URL -f scripts/validate_nve_load.sql")


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
