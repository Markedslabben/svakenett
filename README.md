# Svake Nett Analyse - National Weak Grid Analysis

Geospatial analysis system for identifying weak electrical grid areas and potential customers for hybrid solar + battery installations.

**Scope**: 130,250 buildings across all of Norway
**Building Types**: Cabins (fritidsbygg), Residential (bolig), Commercial (other)
**Tech Stack**: Python + PostgreSQL+PostGIS + GeoPandas
**Current Status**: v4 production system with 200x performance optimization

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

- **buildings**: All building locations (130,250 buildings) with type classification
- **transformers_new**: Transformer locations across Norway
- **power_lines_new**: Power line geometries with voltage classifications
- **distribution_lines_11_24kv**: Materialized view of 11-24 kV distribution lines (9,316 lines)
- **weak_grid_candidates_v4**: Final weak grid candidates (21 buildings) with risk scoring

### Key Indexes

- **GiST spatial indexes**: Fast geospatial queries (distance calculations, spatial joins)
- **B-tree indexes**: Efficient filtering on risk scores, tier classifications
- **Composite indexes**: Optimized for transformer distance and load density queries

---

## Development Workflow

### Data Acquisition (Complete)

NVE data successfully loaded into PostgreSQL+PostGIS:

```bash
# Buildings: 130,250 across Norway
# Transformers: Nationwide coverage
# Power lines: Complete LineString geometries (11-24 kV distribution lines)
```

**Data Source**: NVE (Norwegian Water Resources and Energy Directorate) infrastructure database

### Weak Grid Analysis (v4 - Current System)

Run optimized weak grid filtering:

```bash
# Execute v4 optimized filtering (14 seconds runtime)
psql -U postgres -d svakenett -f sql/optimized_weak_grid_filter_v4.sql
```

**Output**:
- **weak_grid_candidates_v4**: 21 weak grid buildings identified
- **distribution_lines_11_24kv**: Materialized view of distribution infrastructure

**Performance**: 200x faster than baseline approach (14 seconds vs 5-7 hours)

### Export and Validation

```bash
# Export results to CSV
poetry run python scripts/export_weak_grid_candidates.py

# Generate validation reports
poetry run python scripts/generate_weak_grid_report.py
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
4. Connect → Select `weak_grid_candidates_v4` table → Add
5. Style by `composite_risk_score` field for visualization
6. Add `distribution_lines_11_24kv` layer to show power line context

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

## Weak Grid Analysis Methodology (v4)

**Progressive Filtering Approach** - Eliminates 99.95% of buildings BEFORE expensive calculations:

### Filtering Sequence

1. **Transformer Distance >30km** (Highest selectivity: 99.95% eliminated)
   - Filters out buildings with strong grid infrastructure
   - 130,250 → 66 buildings in 1.4 seconds

2. **Distribution Line Proximity <1km** (11-24 kV lines only)
   - Identifies buildings near distribution infrastructure
   - 66 → 62 buildings in 0.04 seconds

3. **Grid Density Calculation** (Expensive operation on small dataset)
   - Count lines within 1km radius
   - 62 buildings in 3.7 seconds (vs 26+ minutes for all buildings)

4. **Low Density Filter** (≤1 line within 1km)
   - Identifies sparse grid areas
   - 62 → 21 buildings instantly

5. **Building/Load Density** (Concentration analysis)
   - Count buildings within 1km (shared grid stress)
   - Final classification with risk tiering

### Risk-Based Classification

**Weak Grid Tiers**:
- Tier 1: Extreme (>50km from transformer)
- Tier 2: Severe (30-50km from transformer)

**Load Severity**:
- High load concentration (≥20 buildings)
- Medium load concentration (10-19 buildings)
- Low load concentration (5-9 buildings)
- Isolated building (<5 nearby)

**Composite Risk Score**: `(transformer_distance_m / 1000) × (buildings_within_1km + 1)`

---

## Current Results (v4)

### Final Output
- **21 weak grid candidates** identified
- **All cabins** (Fritidsbygg, bygningstype 161)
- **Geographic cluster**: Postal code 4865
- **Average transformer distance**: 30.2 km
- **Average load concentration**: 44 buildings per candidate
- **Highest risk**: Building 29088 (risk score: 1,645.1)

### Building Distribution
- 0 residential buildings
- 0 commercial buildings
- 21 cabins (remote cabin areas only)

**Explanation**: 30km transformer distance threshold effectively filters to remote cabin areas. Residential buildings typically have closer transformer access and denser grid infrastructure.

---

## Performance Benchmarks

| Operation | Performance Achieved |
|-----------|---------------------|
| Complete weak grid analysis | 14 seconds (was 5-7 hours) |
| Transformer distance filter | 1.4 seconds (99.95% eliminated) |
| Grid density calculation | 3.7 seconds (was 26+ minutes) |
| Building density calculation | 8.8 seconds |
| Overall speedup | **200x faster** |
| Computational reduction | **99.95% fewer spatial operations** |

---

## Data Sources

- **NVE Infrastructure Data**: Buildings, transformers, power lines across Norway - [nve.no](https://www.nve.no)
  - 130,250 buildings (all types)
  - Nationwide transformer coverage
  - 9,316 distribution lines (11-24 kV) with complete LineString geometries
- **Building Classification**: Fritidsbygg (cabins), Bolig (residential), Other (commercial)

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

## Project Status

1. ✅ Docker + PostgreSQL+PostGIS setup
2. ✅ NVE data loaded (130,250 buildings, transformers, power lines)
3. ✅ Weak grid filtering v4 implemented (200x performance improvement)
4. ✅ 21 weak grid candidates identified with risk scoring
5. ✅ Validated with ChatGPT review (Grade: B+ Very Good)
6. ⏳ Field validation and visualization
7. ⏳ Economic analysis layer (solar irradiance, ROI calculation)

---

## Support

- **PostgreSQL Consultant**: Available for ad-hoc questions
- **QGIS Experience**: Extensive experience with geospatial visualization
- **Grid Tools**: Access to grid infrastructure data for validation

---

## License

Proprietary - Norsk Solkraft AS

---

**Last Updated**: 2025-11-24 (v4 system documentation)
