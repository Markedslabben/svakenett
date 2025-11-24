#!/usr/bin/env python3
"""
Download Kartverket N50 building data for Agder region

This script downloads building location data from Kartverket's open data portal.
N50 Kartdata contains building footprints and points for Norway.

Usage:
    python scripts/01_download_n50_data.py --region agder
"""

import argparse
import os
from pathlib import Path
import requests
from loguru import logger
from tqdm import tqdm


# Kartverket N50 data URLs (GeoJSON format)
# Note: These URLs are examples and need to be verified with actual Kartverket API
N50_URLS = {
    "agder": {
        "buildings": "https://nedlasting.geonorge.no/geonorge/Basisdata/N50Kartdata/GeoJSON/",
        "description": "Agder fylke (Aust-Agder + Vest-Agder municipalities)",
        "municipalities": [
            "0901",  # Kristiansand
            "0904",  # Grimstad
            "0906",  # Arendal
            "1001",  # Kristiansand (new codes after 2020 reform)
            "4201",  # Lindesnes
            "4202",  # Lyngdal
            # Add all Agder municipalities
        ]
    }
}


def download_file(url: str, destination: Path, chunk_size: int = 8192) -> bool:
    """
    Download file with progress bar.

    Args:
        url: URL to download from
        destination: Local file path to save to
        chunk_size: Download chunk size in bytes

    Returns:
        True if successful, False otherwise
    """
    try:
        logger.info(f"Downloading: {url}")

        response = requests.get(url, stream=True)
        response.raise_for_status()

        total_size = int(response.headers.get('content-length', 0))

        destination.parent.mkdir(parents=True, exist_ok=True)

        with open(destination, 'wb') as f, tqdm(
            total=total_size,
            unit='B',
            unit_scale=True,
            desc=destination.name
        ) as pbar:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if chunk:
                    f.write(chunk)
                    pbar.update(len(chunk))

        logger.success(f"✓ Downloaded: {destination}")
        return True

    except Exception as e:
        logger.error(f"✗ Download failed: {e}")
        return False


def download_n50_agder(output_dir: Path) -> bool:
    """
    Download N50 building data for Agder region.

    Args:
        output_dir: Directory to save downloaded files

    Returns:
        True if all downloads successful
    """
    logger.info("Starting N50 data download for Agder region...")

    # NOTE: This is a placeholder implementation
    # The actual Kartverket N50 data access requires:
    # 1. Checking Geonorge.no for current download URLs
    # 2. Possibly using WFS (Web Feature Service) API
    # 3. Filtering by municipality codes for Agder

    logger.warning("⚠ MANUAL STEP REQUIRED:")
    logger.warning("   Visit: https://kartkatalog.geonorge.no/")
    logger.warning("   Search for: 'N50 Kartdata'")
    logger.warning("   Download GeoJSON or GML format for Agder fylke")
    logger.warning("   Save to: data/raw/n50_buildings_agder.geojson")
    logger.warning("")
    logger.info("Alternative: Use Geonorge API or WFS service")
    logger.info("API docs: https://www.geonorge.no/aktuelt/om-geonorge/bruke-geonorge/")

    # Placeholder: Check if file already exists
    expected_file = output_dir / "n50_buildings_agder.geojson"
    if expected_file.exists():
        logger.success(f"✓ File already exists: {expected_file}")
        return True
    else:
        logger.error(f"✗ File not found: {expected_file}")
        logger.error("   Please download manually from Geonorge.no")
        return False


def filter_cabins_from_n50(input_file: Path, output_file: Path) -> bool:
    """
    Filter N50 buildings to extract only cabins (fritidsbebyggelse).

    Args:
        input_file: N50 GeoJSON file with all buildings
        output_file: Output file with cabins only

    Returns:
        True if successful
    """
    try:
        import geopandas as gpd

        logger.info(f"Reading N50 data: {input_file}")
        buildings_gdf = gpd.read_file(input_file)

        logger.info(f"Total buildings: {len(buildings_gdf):,}")

        # Filter for cabins
        # N50 uses "objtype" field with values like:
        # - "Fritidsbygning" (cabin/vacation home)
        # - "Bygning" (general building)
        # Adjust filter based on actual N50 schema

        if 'objtype' in buildings_gdf.columns:
            cabins_gdf = buildings_gdf[
                buildings_gdf['objtype'].str.contains('fritid', case=False, na=False)
            ].copy()
        else:
            logger.warning("⚠ 'objtype' column not found, using all buildings")
            cabins_gdf = buildings_gdf.copy()

        logger.info(f"Filtered cabins: {len(cabins_gdf):,}")

        # Ensure CRS is WGS84 (EPSG:4326) for PostgreSQL
        if cabins_gdf.crs != "EPSG:4326":
            logger.info(f"Converting CRS from {cabins_gdf.crs} to EPSG:4326")
            cabins_gdf = cabins_gdf.to_crs("EPSG:4326")

        # Save filtered data
        output_file.parent.mkdir(parents=True, exist_ok=True)
        cabins_gdf.to_file(output_file, driver='GeoJSON')

        logger.success(f"✓ Saved {len(cabins_gdf):,} cabins to: {output_file}")
        return True

    except Exception as e:
        logger.error(f"✗ Filtering failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Download Kartverket N50 building data")
    parser.add_argument(
        "--region",
        type=str,
        default="agder",
        choices=["agder"],
        help="Region to download (currently only 'agder' supported)"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/raw"),
        help="Output directory for downloaded files"
    )

    args = parser.parse_args()

    # Download N50 data
    success = download_n50_agder(args.output_dir)

    if success:
        logger.success("✓ N50 data download complete")
        logger.info("Next step: python scripts/02_download_kile_data.py")
    else:
        logger.error("✗ Download incomplete - see warnings above")
        logger.info("Manual download required from: https://kartkatalog.geonorge.no/")

    return 0 if success else 1


if __name__ == "__main__":
    exit(main())
