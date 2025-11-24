"""
Database connection and utilities for PostgreSQL + PostGIS
"""

import os
from typing import Optional
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from dotenv import load_dotenv
from loguru import logger
import geopandas as gpd

load_dotenv()


def get_engine(database_url: Optional[str] = None) -> Engine:
    """
    Create SQLAlchemy engine for PostgreSQL connection.

    Args:
        database_url: PostgreSQL connection string. If None, reads from DATABASE_URL env var.

    Returns:
        SQLAlchemy Engine instance

    Example:
        >>> engine = get_engine()
        >>> with engine.connect() as conn:
        ...     result = conn.execute(text("SELECT PostGIS_Version()"))
    """
    if database_url is None:
        database_url = os.getenv("DATABASE_URL")

    if not database_url:
        raise ValueError(
            "DATABASE_URL not found. Set DATABASE_URL environment variable or pass database_url parameter."
        )

    engine = create_engine(database_url, echo=False)
    logger.info(f"Connected to database: {database_url.split('@')[1] if '@' in database_url else 'local'}")

    return engine


def test_connection() -> bool:
    """
    Test PostgreSQL + PostGIS connection.

    Returns:
        True if connection successful, False otherwise
    """
    try:
        engine = get_engine()
        with engine.connect() as conn:
            # Test PostGIS
            result = conn.execute(text("SELECT PostGIS_Version()"))
            version = result.fetchone()[0]
            logger.success(f"✓ PostGIS connection successful: {version}")

            # Test database
            result = conn.execute(text("SELECT current_database()"))
            db_name = result.fetchone()[0]
            logger.success(f"✓ Connected to database: {db_name}")

            return True

    except Exception as e:
        logger.error(f"✗ Database connection failed: {e}")
        return False


def load_geodataframe(
    table_name: str,
    geom_col: str = "geometry",
    where: Optional[str] = None,
    limit: Optional[int] = None,
) -> gpd.GeoDataFrame:
    """
    Load data from PostGIS table as GeoDataFrame.

    Args:
        table_name: Name of the table to query
        geom_col: Name of the geometry column (default: 'geometry')
        where: Optional WHERE clause (e.g., "score_balanced > 70")
        limit: Optional row limit

    Returns:
        GeoDataFrame with spatial data

    Example:
        >>> cabins_gdf = load_geodataframe('cabins', where='score_balanced > 70', limit=100)
    """
    engine = get_engine()

    query = f"SELECT * FROM {table_name}"
    if where:
        query += f" WHERE {where}"
    if limit:
        query += f" LIMIT {limit}"

    logger.info(f"Loading data from {table_name}...")
    gdf = gpd.read_postgis(query, engine, geom_col=geom_col)
    logger.success(f"✓ Loaded {len(gdf):,} rows from {table_name}")

    return gdf


def save_geodataframe(
    gdf: gpd.GeoDataFrame,
    table_name: str,
    if_exists: str = "append",
    create_spatial_index: bool = True,
) -> None:
    """
    Save GeoDataFrame to PostGIS table.

    Args:
        gdf: GeoDataFrame to save
        table_name: Target table name
        if_exists: 'fail', 'replace', or 'append' (default: 'append')
        create_spatial_index: Create GiST spatial index (default: True)

    Example:
        >>> cabins_gdf = gpd.read_file('cabins.geojson')
        >>> save_geodataframe(cabins_gdf, 'cabins', if_exists='replace')
    """
    engine = get_engine()

    logger.info(f"Saving {len(gdf):,} rows to {table_name}...")

    # Save to PostGIS
    gdf.to_postgis(
        table_name,
        engine,
        if_exists=if_exists,
        index=True,
    )

    # Create spatial index if requested
    if create_spatial_index and if_exists == "replace":
        index_name = f"idx_{table_name}_geom"
        with engine.connect() as conn:
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS {index_name} ON {table_name} USING GIST(geometry)"))
            conn.commit()
            logger.success(f"✓ Created spatial index: {index_name}")

    logger.success(f"✓ Saved {len(gdf):,} rows to {table_name}")


def execute_sql_file(sql_file_path: str) -> None:
    """
    Execute SQL file against the database.

    Args:
        sql_file_path: Path to .sql file

    Example:
        >>> execute_sql_file('sql/01_init_schema.sql')
    """
    engine = get_engine()

    logger.info(f"Executing SQL file: {sql_file_path}")

    with open(sql_file_path, "r") as f:
        sql_content = f.read()

    with engine.connect() as conn:
        conn.execute(text(sql_content))
        conn.commit()

    logger.success(f"✓ SQL file executed: {sql_file_path}")


if __name__ == "__main__":
    # Test connection when run directly
    print("Testing PostgreSQL + PostGIS connection...")
    success = test_connection()
    exit(0 if success else 1)
