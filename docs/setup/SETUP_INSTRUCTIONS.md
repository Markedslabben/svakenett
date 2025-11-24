# Svakenett MVP - Setup Instructions

Complete setup guide to get the Agder MVP running in 30 minutes.

---

## Prerequisites

Before starting, ensure you have:

- ✅ **Docker Desktop** installed and running
- ✅ **Python 3.11+** installed
- ✅ **Poetry** installed (Python dependency manager)
- ✅ **Git** (optional, for version control)
- ✅ **QGIS** (optional, for visual validation)

### Install Poetry (if not already installed)

```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Or on Windows (PowerShell):
```powershell
(Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing).Content | python -
```

---

## Step-by-Step Setup

### 1. Navigate to Project Directory

```bash
cd /mnt/c/users/klaus/klauspython/svakenett

# Or on Windows:
# cd C:\users\klaus\klauspython\svakenett
```

### 2. Start PostgreSQL+PostGIS

```bash
# Start Docker container
docker-compose up -d

# Verify container is running
docker ps

# Expected output:
# CONTAINER ID   IMAGE                    STATUS                   PORTS
# xxxxx          postgis/postgis:16-3.4   Up 5 seconds (healthy)   0.0.0.0:5432->5432/tcp
```

The database schema is **automatically initialized** when the container starts (via `sql/01_init_schema.sql`).

### 3. Install Python Dependencies

```bash
# Install all dependencies
poetry install

# This creates a virtual environment and installs:
# - geopandas, pandas, numpy (data processing)
# - sqlalchemy, psycopg2-binary (database)
# - shapely, pyproj (geospatial)
# - folium, plotly (visualization)
# - loguru, tqdm (utilities)
# - pytest, black, ruff (development tools)
```

### 4. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# The default settings work for local Docker setup
# Edit .env only if you need custom configuration
```

Default `.env` settings:
```
DATABASE_URL=postgresql://postgres:weakgrid2024@localhost:5432/svakenett
```

### 5. Verify Setup

```bash
# Activate Poetry virtual environment
poetry shell

# Run setup verification script
python scripts/setup_check.py
```

Expected output:
```
✓ Docker is running
✓ PostgreSQL container: Up 2 minutes (healthy)
✓ PostgreSQL connection works
✓ PostGIS extension available
✓ Python: geopandas installed
✓ Python: pandas installed
✓ Database schema initialized (8 tables)

✓ All checks passed (6/6)
```

If any checks fail, see **Troubleshooting** section below.

---

## Quick Test: Database Connection

```bash
# Test PostgreSQL connection from Python
poetry run python -c "from svakenett.db import test_connection; test_connection()"
```

Expected output:
```
✓ PostGIS connection successful: 3.4.0
✓ Connected to database: svakenett
```

---

## Next Steps: Data Acquisition (Day 1-7)

### Option 1: PostGIS SQL Dump (RECOMMENDED - Fastest!)

**Kartverket N50 PostGIS Dump**:
1. Visit: https://kartkatalog.geonorge.no/
2. Search: "N50 Kartdata"
3. Select: Agder fylke
4. **Format**: "PostGIS - SQL dump for direkte import i PostgreSQL/PostGIS"
5. Save to: `data/raw/n50_agder_postgis.dump`
6. Load with: `./scripts/02_load_n50_postgis_dump.sh`

**Advantages**:
- ✅ Direct PostgreSQL import (no conversion!)
- ✅ Spatial indexes included
- ✅ Loads in ~30 seconds (vs 5-10 minutes with other formats)
- ✅ No Python/GeoPandas needed

**NVE KILE Statistics**:
1. Visit: https://www.nve.no/energi/energisystem/kraftsystemet/kile/
2. Download: KILE data for 2023
3. Save to: `data/raw/kile_statistics_2023.csv`

### Option 2: Other Formats (if PostGIS dump unavailable)

Use GeoJSON or GeoPackage (slower but works):
1. Download GeoJSON/GeoPackage format from Geonorge
2. Save to: `data/raw/n50_buildings_agder.geojson`
3. Use Python scripts for conversion

### Option 2: Automated Download (Requires API Access)

```bash
# Download N50 building data
poetry run python scripts/01_download_n50_data.py --region agder

# Download KILE statistics
poetry run python scripts/02_download_kile_data.py --year 2023

# Process and load to PostgreSQL
poetry run python scripts/03_load_data_to_postgres.py
```

**Note**: Automated scripts are placeholders and require Geonorge API keys.

---

## Connecting QGIS (Visual Validation)

QGIS allows you to visualize the data in PostgreSQL and validate the scoring model.

### Steps:

1. Open QGIS
2. **Layer** → **Add Layer** → **Add PostGIS Layers**
3. Click **New** to create a new connection
4. Enter connection details:
   - **Name**: `svakenett_local`
   - **Host**: `localhost`
   - **Port**: `5432`
   - **Database**: `svakenett`
   - **Username**: `postgres`
   - **Password**: `weakgrid2024`
   - **SSL mode**: `disable` (for local development)
5. Click **Test Connection** (should succeed)
6. Click **OK**
7. Select `cabins` table → Click **Add**
8. Style by `score_balanced` field:
   - Right-click layer → **Properties** → **Symbology**
   - Change to **Graduated**
   - Select **score_balanced** as field
   - Choose color ramp (e.g., Red to Green)
   - Click **Classify**

---

## Project Structure Overview

```
svakenett/
├── docker-compose.yml          # ✅ PostgreSQL+PostGIS setup
├── pyproject.toml              # ✅ Python dependencies
├── .env.example                # ✅ Environment template
├── README.md                   # ✅ Project documentation
├── SETUP_INSTRUCTIONS.md       # ✅ This file
│
├── sql/
│   └── 01_init_schema.sql     # ✅ Database schema (auto-loaded)
│
├── src/svakenett/
│   ├── __init__.py            # ✅ Package initialization
│   ├── db.py                  # ✅ Database utilities
│   ├── data_acquisition.py    # ⏳ Data download (to be created)
│   ├── scoring.py             # ⏳ Scoring algorithm (to be created)
│   └── validation.py          # ⏳ Validation metrics (to be created)
│
├── scripts/
│   ├── setup_check.py         # ✅ Setup verification
│   ├── 01_download_n50_data.py    # ✅ N50 download (placeholder)
│   ├── 02_download_kile_data.py   # ⏳ KILE download (to be created)
│   └── 03_load_data_to_postgres.py # ⏳ Data loading (to be created)
│
├── tests/                     # ⏳ Test suite (to be created)
│
└── data/
    ├── raw/                   # Download source data here
    ├── processed/             # Processed GeoJSON/CSV files
    └── postgres/              # PostgreSQL data (managed by Docker)
```

Legend:
- ✅ = Created and ready
- ⏳ = To be created during implementation

---

## Troubleshooting

### Docker container not starting

```bash
# Check Docker is running
docker --version

# Check container logs
docker logs svakenett-postgis

# Remove and recreate container
docker-compose down
docker-compose up -d
```

### Port 5432 already in use

If you have another PostgreSQL instance running:

**Option 1**: Stop the other PostgreSQL instance
**Option 2**: Change port in `docker-compose.yml`:
```yaml
ports:
  - "5433:5432"  # Use port 5433 instead
```

Then update `.env`:
```
DATABASE_URL=postgresql://postgres:weakgrid2024@localhost:5433/svakenett
```

### "psycopg2" import errors

```bash
# On Ubuntu/WSL:
sudo apt-get install libpq-dev python3-dev

# On macOS:
brew install postgresql

# Then reinstall:
poetry install
```

### "PostGIS extension not found"

```bash
# Manually create extension
docker exec -it svakenett-postgis psql -U postgres -d svakenett -c "CREATE EXTENSION postgis;"

# Verify
docker exec -it svakenett-postgis psql -U postgres -d svakenett -c "SELECT PostGIS_Version();"
```

### Python virtual environment issues

```bash
# Remove existing venv
poetry env remove --all

# Recreate
poetry install

# Activate
poetry shell
```

---

## Development Commands Reference

### Docker

```bash
docker-compose up -d          # Start PostgreSQL
docker-compose down           # Stop PostgreSQL
docker-compose logs -f        # View logs
docker-compose restart        # Restart PostgreSQL
docker exec -it svakenett-postgis psql -U postgres -d svakenett  # Open psql
```

### Poetry

```bash
poetry install                # Install dependencies
poetry shell                  # Activate virtual environment
poetry add <package>          # Add new dependency
poetry update                 # Update all dependencies
```

### Database

```bash
# Connect via psql
docker exec -it svakenett-postgis psql -U postgres -d svakenett

# Run SQL file
docker exec -i svakenett-postgis psql -U postgres -d svakenett < sql/01_init_schema.sql

# Backup database
docker exec svakenett-postgis pg_dump -U postgres svakenett > backup.sql

# Restore database
docker exec -i svakenett-postgis psql -U postgres -d svakenett < backup.sql
```

### Testing

```bash
poetry run pytest                    # Run all tests
poetry run pytest --cov              # Run with coverage
poetry run pytest tests/test_db.py   # Run specific test
```

---

## Performance Checks

Once data is loaded, verify performance benchmarks:

```bash
# Load 15k cabins (should be < 5 seconds)
poetry run python -c "
from svakenett.db import load_geodataframe
import time
start = time.time()
gdf = load_geodataframe('cabins')
print(f'Loaded {len(gdf):,} cabins in {time.time()-start:.2f} seconds')
"

# Calculate all scores (should be < 30 seconds)
poetry run python scripts/04_calculate_scores.py
```

---

## Support Resources

- **PostgreSQL Consultant**: Available for ad-hoc technical questions
- **QGIS Documentation**: https://docs.qgis.org/
- **PostGIS Documentation**: https://postgis.net/documentation/
- **GeoPandas Documentation**: https://geopandas.org/
- **Kartverket API**: https://www.geonorge.no/

---

## Timeline Reminder

**Day 1 (Today)**: Setup complete ✅
**Day 2-7**: Data acquisition and loading
**Day 8-10**: Scoring model implementation
**Day 11-12**: Validation and export

**Total MVP Duration**: 2.5 weeks (12 work days)

---

**Status**: ✅ Infrastructure ready for development

**Next Action**: Download Kartverket N50 data (see "Next Steps" section above)

---

**Last Updated**: 2025-11-22
