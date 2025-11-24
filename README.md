# Svake Nett Analyse - MVP Implementation (Agder)

Geospatial analysis system for identifying weak electrical grid areas and potential customers for hybrid solar + battery installations.

**Target**: 15,000 cabins in Agder region
**Timeline**: 2.5 weeks (12 work days)
**Tech Stack**: Python + PostgreSQL+PostGIS + GeoPandas

---

## Quick Start

### 1. Prerequisites

- Docker Desktop (for PostgreSQL+PostGIS)
- Python 3.11+
- Poetry (Python dependency management)
- QGIS (optional, for visual validation)

### 2. Setup PostgreSQL+PostGIS

```bash
# Start PostgreSQL+PostGIS container
docker-compose up -d

# Verify PostGIS is running
docker ps

# Test connection
python src/svakenett/db.py
```

Expected output:
```
✓ PostGIS connection successful: 3.4.0
✓ Connected to database: svakenett
```

### 3. Install Python Dependencies

```bash
# Install Poetry (if not already installed)
curl -sSL https://install.python-poetry.org | python3 -

# Install project dependencies
poetry install

# Activate virtual environment
poetry shell
```

### 4. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env if needed (default settings work for local Docker)
```

### 5. Initialize Database Schema

The database schema is automatically created when the Docker container starts (via `/sql/01_init_schema.sql`).

To verify:
```bash
poetry run python -c "from svakenett.db import test_connection; test_connection()"
```

---

## Project Structure

```
svakenett/
├── docker-compose.yml          # PostgreSQL+PostGIS configuration
├── pyproject.toml              # Python dependencies
├── .env.example                # Environment variable template
├── README.md                   # This file
│
├── sql/                        # Database schema and migrations
│   └── 01_init_schema.sql     # Initial database setup
│
├── src/
│   └── svakenett/             # Main Python package
│       ├── __init__.py
│       ├── db.py              # Database utilities
│       ├── data_acquisition.py  # Download and process data sources
│       ├── scoring.py         # Weak grid scoring algorithms
│       └── validation.py      # Model validation and metrics
│
├── tests/                     # Test suite
│   ├── test_db.py
│   ├── test_scoring.py
│   └── test_validation.py
│
├── data/
│   ├── raw/                   # Downloaded source data
│   ├── processed/             # Processed GeoJSON/CSV files
│   └── postgres/              # PostgreSQL data directory (created by Docker)
│
└── claudedocs/                # Claude-generated documentation
    ├── MVP_IMPLEMENTATION_PLAN_AGDER.md
    ├── UPDATE_POSTGRESQL_SUMMARY.md
    └── SCALABILITY_ASSESSMENT.md
```

---

## Database Schema

### Core Tables

- **cabins**: Individual cabin locations with weak grid scores
- **grid_companies**: Grid company KILE statistics (SAIDI/SAIFI)
- **postal_codes**: Postal code boundaries
- **municipalities**: Municipality boundaries
- **postal_code_scores**: GDPR-compliant aggregated scores (≥5 cabins per postal code)

### Key Indexes

- **GiST spatial indexes**: Fast geospatial queries (distance calculations, spatial joins)
- **B-tree indexes**: Efficient filtering on postal codes, scores
- **Materialized view**: `mv_cabin_summary` for dashboard queries

---

## Development Workflow

### Day 1-7: Data Acquisition

**RECOMMENDED: Use PostGIS SQL Dump** (direct PostgreSQL import, no conversion needed):

```bash
# 1. Download N50 PostGIS dump from Geonorge.no
#    Visit: https://kartkatalog.geonorge.no/
#    Search: "N50 Kartdata"
#    Region: Agder fylke
#    Format: PostGIS - SQL dump
#    Save to: data/raw/n50_agder_postgis.dump

# 2. Load directly into PostgreSQL (30 seconds!)
./scripts/02_load_n50_postgis_dump.sh data/raw/n50_agder_postgis.dump

# 3. Download NVE KILE statistics
poetry run python scripts/03_download_kile_data.py --year 2023
```

**Alternative** (if PostGIS dump unavailable):
```bash
# Use GeoJSON/GeoPackage with GeoPandas
poetry run python scripts/01_download_n50_data.py --region agder
poetry run python scripts/03_load_data_to_postgres.py
```

### Day 8-10: Scoring Model

```bash
# Calculate weak grid scores for all cabins
poetry run python scripts/04_calculate_scores.py

# Generate GDPR-compliant postal code aggregations
poetry run python scripts/05_aggregate_postal_codes.py

# Validate scoring model
poetry run python scripts/06_validate_scores.py
```

### Day 11-12: Validation & Export

```bash
# Generate validation report
poetry run python scripts/07_generate_validation_report.py

# Export results to CSV for CRM import
poetry run python scripts/08_export_csv.py
```

---

## Connecting QGIS to PostgreSQL

1. Open QGIS
2. Layer → Add Layer → Add PostGIS Layers
3. New connection:
   - **Name**: `svakenett_local`
   - **Host**: `localhost`
   - **Port**: `5432`
   - **Database**: `svakenett`
   - **User**: `postgres`
   - **Password**: `weakgrid2024`
4. Connect → Select `cabins` table → Add
5. Style by `score_balanced` field for visualization

---

## Testing

```bash
# Run all tests
poetry run pytest

# Run with coverage
poetry run pytest --cov=src/svakenett --cov-report=html

# Run specific test file
poetry run pytest tests/test_scoring.py -v
```

---

## Scoring Algorithm

**Weighted Formula** (0-100 scale):

```
score = (KILE_score * 0.40) +
        (distance_score * 0.30) +
        (terrain_score * 0.20) +
        (municipality_score * 0.10)
```

### Three Scoring Profiles

- **Conservative** (score ≥ 75): High confidence, estimated 3,000 cabins
- **Balanced** (score ≥ 60): Recommended default, estimated 7,500 cabins
- **Aggressive** (score ≥ 45): Maximum reach, estimated 15,000 cabins

---

## GDPR Compliance

- **Aggregation**: Results aggregated to postal code level (minimum 5 cabins)
- **No Individual Targeting**: Individual properties not exported
- **Legitimate Interest**: Weak grid = publicly observable condition
- **Geo-targeted Ads**: Facebook/Google ads targeting postal codes only

---

## Performance Benchmarks

| Operation | Target Performance |
|-----------|-------------------|
| Load 15k cabins | < 5 seconds |
| Calculate all scores | < 30 seconds |
| Distance to nearest town (15k cabins) | 2-5 seconds |
| Postal code aggregation | < 10 seconds |
| Full MVP pipeline (Day 1-12) | 2.5 weeks |

---

## Data Sources

- **NVE KILE**: Grid outage statistics (SAIDI/SAIFI) - [nve.no](https://www.nve.no)
- **Kartverket N50**: Building locations - [kartverket.no](https://kartkatalog.geonorge.no/)
- **SSB**: Population and municipality data - [ssb.no](https://www.ssb.no)
- **Matrikkelen**: Property registry (deferred to Phase 2)

---

## Troubleshooting

### PostgreSQL connection refused

```bash
# Check Docker container is running
docker ps

# Check logs
docker logs svakenett-postgis

# Restart container
docker-compose restart
```

### "PostGIS extension not found"

The schema initialization should create PostGIS automatically. If not:

```bash
docker exec -it svakenett-postgis psql -U postgres -d svakenett -c "CREATE EXTENSION postgis;"
```

### Python import errors

```bash
# Ensure you're in Poetry virtualenv
poetry shell

# Reinstall dependencies
poetry install
```

---

## Next Steps

1. ✅ Docker + PostgreSQL+PostGIS setup (30 min)
2. ⏳ Download Kartverkat N50 data (Day 1-3)
3. ⏳ Download NVE KILE statistics (Day 4-5)
4. ⏳ Load data to PostgreSQL (Day 6-7)
5. ⏳ Implement scoring algorithm (Day 8-9)
6. ⏳ Validate and refine (Day 10-11)
7. ⏳ Export results (Day 12)

---

## Support

- **PostgreSQL Consultant**: Available for ad-hoc questions
- **QGIS Experience**: Extensive experience with geospatial visualization
- **Grid Tools**: Access to grid infrastructure data for validation

---

## License

Proprietary - Norsk Solkraft AS

---

**Last Updated**: 2025-11-22
