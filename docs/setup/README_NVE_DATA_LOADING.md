# NVE Grid Infrastructure Data Loading

Complete guide for loading Norwegian grid infrastructure data into PostgreSQL+PostGIS for weak grid identification.

## Overview

This pipeline loads NVE (Norwegian Water Resources and Energy Directorate) grid data to enable precise identification of weak grid areas in Agder county for hybrid solar+battery installations.

**Data Source**: NVE open data (GDB format)
**Coverage**: Agder fylke (25 municipalities)
**Records**: ~72,000 grid infrastructure features
**Output**: Cabin-level weak grid scores (0-100)

---

## What Gets Loaded

### Infrastructure Data
- **9,715 power lines** (Kraftlinje + Sjøkabel)
  - 72% are 22kV distribution lines (our target)
  - Includes voltage, age, owner, and spatial data
- **62,559 power poles** (Mast)
  - 85% are distribution-level poles
  - Used for grid density analysis
- **106 transformer stations** (Transformatorstasjon)
  - Used for distance-to-source calculations

### Derived Metrics (added to `cabins` table)
- `distance_to_line_m` - Distance to nearest 22kV line
- `grid_density_1km` - Power line count within 1km
- `nearest_line_voltage_kv` - Voltage level (22kV = weak)
- `nearest_line_age_years` - Infrastructure age
- `weak_grid_score` - Composite 0-100 score

---

## Prerequisites

### 1. Database Setup

You need PostgreSQL with PostGIS extension:

```bash
# Check PostgreSQL is running
psql --version

# Check PostGIS is installed
psql -d svakenett -c "SELECT postgis_version();"
```

If PostGIS is not installed:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

### 2. Python Dependencies

Install required packages via conda:

```bash
# Activate your conda environment
conda activate svakenett

# Install dependencies
conda install -c conda-forge geopandas fiona sqlalchemy psycopg2
```

Verify installation:
```bash
python3 -c "import geopandas, fiona, sqlalchemy; print('✓ Dependencies OK')"
```

### 3. NVE Data Files

Ensure the GDB file is in place:

```bash
ls -lh /mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure/NVEData.gdb
```

If missing, download from NVE's open data portal.

---

## Quick Start (Automated Pipeline)

### Step 1: Set Database Connection

```bash
export DATABASE_URL='postgresql://postgres:your_password@localhost:5432/svakenett'
```

**Make it permanent** (add to `~/.bashrc`):
```bash
echo 'export DATABASE_URL="postgresql://postgres:your_password@localhost:5432/svakenett"' >> ~/.bashrc
source ~/.bashrc
```

### Step 2: Run Master Pipeline

```bash
cd /mnt/c/Users/klaus/klauspython/svakenett
bash scripts/load_nve_infrastructure_complete.sh
```

This runs all 7 steps automatically:
1. ✅ Create database schema
2. ✅ Load power lines (9,715 records)
3. ✅ Load power poles (62,559 records)
4. ✅ Load transformers (106 records)
5. ✅ Validate data integrity
6. ✅ Calculate cabin distances (~10-30 min)
7. ✅ Calculate weak grid scores

**Expected Duration**: 15-45 minutes depending on cabin count.

**Log File**: `logs/nve_load_YYYYMMDD_HHMMSS.log`

---

## Manual Step-by-Step Execution

If you prefer to run each step manually:

### Step 1: Create Schema

```bash
psql $DATABASE_URL -f sql/nve_infrastructure_schema.sql
```

Creates 3 tables:
- `nve_power_lines`
- `nve_power_poles`
- `nve_transformers`

### Step 2: Load Power Lines

```bash
python3 scripts/load_nve_power_lines.py
```

Loads Kraftlinje (overhead) + Sjøkabel (submarine) into `nve_power_lines`.

### Step 3: Load Power Poles

```bash
python3 scripts/load_nve_power_poles.py
```

### Step 4: Load Transformers

```bash
python3 scripts/load_nve_transformers.py
```

### Step 5: Validate Data

```bash
psql $DATABASE_URL -f scripts/validate_nve_load.sql
```

Checks:
- ✅ Record counts match expected ranges
- ✅ CRS is WGS84 (EPSG:4326)
- ✅ Spatial indexes are created
- ✅ 22kV distribution lines identified
- ✅ Grid company linkage verified

### Step 6: Calculate Cabin Distances

```bash
psql $DATABASE_URL -f scripts/calculate_cabin_grid_distances.sql
```

**Warning**: This step is computationally intensive (10-30 minutes).
Processes in batches to avoid memory issues.

### Step 7: Calculate Weak Grid Scores

```bash
psql $DATABASE_URL -f scripts/calculate_weak_grid_scores.sql
```

Applies composite scoring algorithm:
- **40%** Distance to line (>500m = weak)
- **25%** Grid density (<3 lines/km² = weak)
- **15%** KILE costs (from `grid_companies` table)
- **10%** Voltage level (22kV = weak)
- **10%** Grid age (>30 years = weak)

---

## Verify Results

### Check Data Loaded Successfully

```sql
-- Record counts
SELECT 'Power Lines' as table_name, COUNT(*) FROM nve_power_lines
UNION ALL
SELECT 'Power Poles', COUNT(*) FROM nve_power_poles
UNION ALL
SELECT 'Transformers', COUNT(*) FROM nve_transformers;

-- Expected:
-- Power Lines:  ~10,000
-- Power Poles:  ~62,500
-- Transformers: ~100
```

### Check Weak Grid Scores

```sql
-- Score distribution
SELECT
    CASE
        WHEN weak_grid_score >= 90 THEN 'Excellent (90-100)'
        WHEN weak_grid_score >= 70 THEN 'Good (70-89)'
        WHEN weak_grid_score >= 50 THEN 'Moderate (50-69)'
        ELSE 'Poor (0-49)'
    END as category,
    COUNT(*) as cabins,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY 1
ORDER BY MIN(weak_grid_score) DESC;
```

### View Top Prospects

```sql
-- Top 10 highest-scoring cabins
SELECT
    id,
    ROUND(weak_grid_score, 1) as score,
    municipality,
    ROUND(distance_to_line_m, 0) as dist_m,
    grid_density_1km as density,
    nearest_line_voltage_kv as voltage
FROM cabins
WHERE weak_grid_score IS NOT NULL
ORDER BY weak_grid_score DESC
LIMIT 10;
```

---

## Export Results

### Export Top 500 Leads (CSV)

```bash
psql $DATABASE_URL -c "COPY (SELECT * FROM top_500_weak_grid_leads) TO '/tmp/top_500_leads.csv' CSV HEADER;"
```

### Export Full Dataset (GeoJSON for QGIS)

```bash
ogr2ogr -f GeoJSON \
  /mnt/c/Users/klaus/klauspython/svakenett/output/cabins_scored.geojson \
  PG:"$DATABASE_URL" \
  -sql "SELECT id, weak_grid_score, distance_to_line_m, grid_density_1km, municipality, geometry FROM cabins WHERE weak_grid_score >= 70"
```

### Postal Code Aggregates (GDPR Compliant)

```sql
-- Aggregate by postal code (no individual cabin data)
COPY (
    SELECT
        postal_code,
        COUNT(*) as cabin_count,
        ROUND(AVG(weak_grid_score), 1) as avg_score,
        ROUND(AVG(distance_to_line_m), 0) as avg_distance_m,
        ROUND(AVG(grid_density_1km), 1) as avg_density
    FROM cabins
    WHERE weak_grid_score >= 70
    GROUP BY postal_code
    HAVING COUNT(*) >= 3  -- GDPR: minimum 3 cabins per postal code
    ORDER BY avg_score DESC
) TO '/tmp/postal_code_aggregates.csv' CSV HEADER;
```

---

## Visualize in QGIS

### 1. Add PostGIS Connection

- **Layer** → **Add Layer** → **Add PostGIS Layers**
- **New Connection**:
  - Name: `svakenett`
  - Host: `localhost`
  - Port: `5432`
  - Database: `svakenett`
  - Username: `postgres`
  - Password: `your_password`

### 2. Add Layers

Add these layers to your map:
1. **Cabins** (symbolized by `weak_grid_score`)
2. **NVE Power Lines** (`nve_power_lines`)
3. **NVE Power Poles** (`nve_power_poles`)
4. **NVE Transformers** (`nve_transformers`)

### 3. Symbolize Cabins by Score

**Graduated Colors**:
- Column: `weak_grid_score`
- Mode: Natural Breaks (Jenks)
- Classes:
  - 0-49: Green (poor prospects)
  - 50-69: Yellow (moderate)
  - 70-89: Orange (good prospects)
  - 90-100: Red (excellent prospects)

### 4. Filter to High-Scoring Cabins

Right-click cabins layer → **Filter**:
```sql
"weak_grid_score" >= 70
```

---

## Troubleshooting

### Issue: "GDB file not found"

```bash
# Check file path
ls -lh /mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure/

# If missing, download from NVE open data portal
```

### Issue: "Cannot connect to database"

```bash
# Check PostgreSQL is running
sudo service postgresql status

# Test connection
psql -h localhost -U postgres -d svakenett -c "SELECT 1;"

# Check DATABASE_URL is set correctly
echo $DATABASE_URL
```

### Issue: "Missing Python dependencies"

```bash
# Reinstall with conda
conda install -c conda-forge geopandas fiona sqlalchemy psycopg2

# Verify
python3 -c "import geopandas; print(geopandas.__version__)"
```

### Issue: "Cabin distance calculation takes too long"

The script processes cabins in batches of 5,000. For large datasets (>15,000 cabins):

1. Monitor progress in real-time:
   ```bash
   tail -f logs/nve_load_*.log
   ```

2. Increase batch size (edit `calculate_cabin_grid_distances.sql`):
   ```sql
   WHERE c.id >= 1 AND c.id < 10000  -- Increase from 5000 to 10000
   ```

3. Run in background:
   ```bash
   bash scripts/load_nve_infrastructure_complete.sh &
   disown
   ```

### Issue: "Invalid geometries detected"

```sql
-- Fix invalid geometries
UPDATE nve_power_lines
SET geometry = ST_MakeValid(geometry)
WHERE NOT ST_IsValid(geometry);
```

---

## Performance Tips

### 1. Spatial Index Optimization

Indexes are created automatically, but you can rebuild if needed:

```sql
REINDEX INDEX idx_nve_power_lines_geom;
REINDEX INDEX idx_nve_power_poles_geom;
```

### 2. Vacuum and Analyze

After loading large datasets:

```sql
VACUUM ANALYZE nve_power_lines;
VACUUM ANALYZE nve_power_poles;
VACUUM ANALYZE nve_transformers;
VACUUM ANALYZE cabins;
```

### 3. Connection Pooling

For repeated queries, use connection pooling:

```python
from sqlalchemy import create_engine
engine = create_engine(os.getenv('DATABASE_URL'), pool_size=10, max_overflow=20)
```

---

## Next Steps

After successful data loading:

1. **Validate Results**
   - Compare scores with existing customer data
   - Verify top-scoring cabins against known weak grid areas

2. **Create Marketing Materials**
   - Export top 500 leads for sales team
   - Generate postal code heatmaps for targeted ads

3. **Integrate with CRM** (Phase 2)
   - Add `weak_grid_score` to PowerOffice/Contracting Works
   - Create automated lead scoring pipeline

4. **Expand to National Coverage** (Phase 2)
   - Repeat process for other counties
   - Scale to all ~455,000 Norwegian cabins

---

## File Structure

```
svakenett/
├── data/
│   └── nve_infrastructure/
│       ├── NVEData.gdb                 # Source GDB file
│       └── Metadata/                   # NVE metadata
├── sql/
│   └── nve_infrastructure_schema.sql   # Database schema
├── scripts/
│   ├── load_nve_power_lines.py         # Load power lines
│   ├── load_nve_power_poles.py         # Load power poles
│   ├── load_nve_transformers.py        # Load transformers
│   ├── validate_nve_load.sql           # Data validation
│   ├── calculate_cabin_grid_distances.sql  # Distance calculations
│   ├── calculate_weak_grid_scores.sql  # Scoring algorithm
│   └── load_nve_infrastructure_complete.sh # Master pipeline
├── logs/
│   └── nve_load_YYYYMMDD_HHMMSS.log   # Execution logs
└── README_NVE_DATA_LOADING.md          # This file
```

---

## Support & Documentation

**NVE Open Data Portal**: https://www.nve.no/energi/energisystem/kraftnett/nettdata/
**PostGIS Documentation**: https://postgis.net/documentation/
**GeoPandas Documentation**: https://geopandas.org/

For questions or issues, contact: klaus@example.com

---

**Last Updated**: 2025-01-22
**Version**: 1.0.0
