# Grid Infrastructure Scoring System - Implementation Plan

## Executive Summary

This plan outlines the complete implementation of a grid infrastructure-based scoring system to identify weak grid cabins as battery system prospects. The system replaces approximate service area analysis with precise grid infrastructure measurements.

**Timeline**: 2-3 hours total execution time
**Prerequisites**: Docker container running, 37,170 cabins loaded, grid companies loaded
**Outcome**: All cabins scored 0-100 based on grid weakness, high-value prospects identified

---

## Phase Overview

| Phase | Description | Est. Time | Can Run Parallel? |
|-------|-------------|-----------|-------------------|
| 1 | Schema Setup | 5 min | No |
| 2 | Data Download | 10-15 min | Yes (4 layers) |
| 3 | Data Load & Transform | 15-20 min | No |
| 4 | Metrics Calculation | 60-90 min | No (batched internally) |
| 5 | Scoring Application | 5-10 min | No |
| 6 | Validation & Export | 5 min | No |

**Total Estimated Time**: 100-145 minutes (1.7-2.4 hours)

---

## Detailed Execution Steps

### Phase 1: Schema Setup (5 minutes)

**Objective**: Create database tables, indexes, and functions for grid infrastructure

**Commands**:
```bash
cd /home/klaus/klauspython/svakenett

# Apply schema changes
docker exec svakenett-postgis psql -U postgres -d svakenett < docs/DATABASE_SCHEMA.sql
```

**Creates**:
- 4 new tables: `power_lines`, `power_poles`, `cables`, `transformers`
- 13 new columns in `cabins` table
- Spatial indexes for performance
- Helper functions for scoring calculations
- Materialized views for analytics

**Validation**:
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d power_lines"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d cabins" | grep score
```

**Expected Output**:
- `power_lines` table with geometry, voltage_kv, owner_orgnr columns
- `cabins` table with new columns: weak_grid_score, score_category, distance_to_line_m, etc.

---

### Phase 2: Data Download (10-15 minutes) - PARALLEL

**Objective**: Download 4 NVE grid infrastructure layers for Agder region

**Command**:
```bash
./scripts/12_download_grid_infrastructure.sh
```

**What It Does**:
- Downloads 4 layers **in parallel** using background processes:
  1. Layer 2: Distribusjonsnett (distribution grid power lines)
  2. Layer 4: Master og stolper (power poles)
  3. Layer 3: Sjøkabler (cables - underground and sea)
  4. Layer 5: Transformatorstasjoner (transformer stations)
- Fetches data from NVE ArcGIS REST API
- Filters to Agder bounding box: (6.5, 57.8) to (9.2, 59.5)
- Saves as GeoJSON files in `data/nve_infrastructure/`

**Parallelization**:
- All 4 downloads run simultaneously (4 background processes)
- Wait for all to complete before proceeding
- Expected speedup: ~75% faster than sequential (15 min vs 60 min)

**Expected Output**:
```
data/nve_infrastructure/
├── power_lines.geojson     (~2000-5000 features)
├── power_poles.geojson     (~5000-15000 features)
├── cables.geojson          (~500-1500 features)
└── transformers.geojson    (~100-500 features)
```

**Validation**:
```bash
ls -lh data/nve_infrastructure/
# Should see 4 .geojson files, each >100KB
```

**Troubleshooting**:
- If download fails: Check NVE API status, verify bounding box coordinates
- If features = 0: May need to adjust bounding box or layer ID
- Retry individual layer: Modify script to download one layer at a time

---

### Phase 3: Data Load & Transform (15-20 minutes)

**Objective**: Load GeoJSON files into PostGIS and transform to clean schema

**Command**:
```bash
./scripts/13_load_grid_infrastructure.sh
```

**What It Does**:
1. Validates all 4 GeoJSON files exist
2. Loads each file into temporary `*_raw` tables using `ogr2ogr`
3. Transforms raw data to clean schema:
   - Extracts relevant fields (eier_orgnr → owner_orgnr, spenning → voltage_kv, aar → year_built)
   - Validates geometries and data types
   - Calculates line/cable lengths
   - Filters invalid years (must be 1900-2030)
4. Drops temporary tables
5. Creates spatial indexes

**Performance Notes**:
- Uses Docker `ogr2ogr` for efficient GeoJSON → PostGIS conversion
- Runs sequentially (dependencies between steps)
- Spatial indexing may take 2-3 minutes for large datasets

**Expected Output**:
```
power_lines:     2000-5000 rows, avg 20-30 years old, 22-132 kV
power_poles:     5000-15000 rows
cables:          500-1500 rows
transformers:    100-500 rows
```

**Validation**:
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT 'power_lines' as table, COUNT(*) FROM power_lines
UNION ALL SELECT 'power_poles', COUNT(*) FROM power_poles
UNION ALL SELECT 'cables', COUNT(*) FROM cables
UNION ALL SELECT 'transformers', COUNT(*) FROM transformers;"
```

**Troubleshooting**:
- If row counts = 0: Check GeoJSON validity, verify field mappings
- If geometry errors: Check SRID transformation (should be EPSG:4326)
- If performance slow: Verify spatial indexes created (`\d power_lines` shows GIST index)

---

### Phase 4: Metrics Calculation (60-90 minutes)

**Objective**: Calculate 5 grid infrastructure metrics for all 37,170 cabins

**Command**:
```bash
./scripts/14_calculate_metrics.sh
```

**What It Does** (in batch mode, 1000 cabins at a time):

#### Metric 1: Distance to Nearest Power Line (20-30 min)
- **Query**: For each cabin, find closest power line using spatial index
- **Calculates**: Distance in meters using `ST_Distance` (geography mode for accuracy)
- **Also captures**: Voltage level, owner organization number
- **Performance**: Uses `CROSS JOIN LATERAL` with `ORDER BY geometry <-> geometry LIMIT 1` for speed
- **Batch size**: 1000 cabins per batch (37 batches total)

#### Metric 2: Grid Density within 1km (20-30 min)
- **Query**: Count power lines within 1000m radius of each cabin
- **Calculates**:
  - Number of lines within 1km
  - Total line length within 1km (kilometers)
- **Performance**: Uses `ST_DWithin(geography, geography, 1000)` with spatial index
- **Interpretation**: 0-2 lines = sparse, 3-5 = moderate, 6+ = dense

#### Metric 3: Average Grid Age (10-15 min)
- **Query**: Average year_built for all lines within 1km
- **Calculates**: `AVG(2025 - year_built)` = average age in years
- **Filters**: Only lines with valid year_built (not NULL)
- **Interpretation**: 0-20 years = modern, 20-40 = aging, 40+ = legacy

#### Metric 4: Distance to Transformer (5-10 min)
- **Query**: Find nearest transformer station
- **Calculates**: Distance in meters
- **Note**: Optional metric, not used in current scoring formula

**Batching Strategy**:
- Processes 1000 cabins at a time to avoid memory issues
- Total batches: 38 (37,170 ÷ 1000)
- Progress indicator shows batch number and offset

**Expected Output**:
```
Total cabins: 37,170
Cabins with distance: 37,170 (100%)
Cabins with density: 37,170 (100%)
Cabins with age: ~35,000 (94%) - some areas may have no lines within 1km

Metric Statistics:
  Distance: min=0m, avg=500m, max=5000m+, median=300m
  Density: min=0, avg=3, max=20+, median=2
  Age: min=0yrs, avg=25yrs, max=60yrs, median=22yrs
```

**Validation**:
```bash
# Check completeness
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
  COUNT(*) as total,
  COUNT(distance_to_line_m) as has_distance,
  COUNT(grid_density_lines_1km) as has_density,
  COUNT(grid_age_years) as has_age
FROM cabins;"

# Sample high-distance cabins (should be remote mountain areas)
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT id, postal_code, ROUND(distance_to_line_m) as dist_m, grid_density_lines_1km
FROM cabins ORDER BY distance_to_line_m DESC LIMIT 10;"
```

**Troubleshooting**:
- If metrics = NULL for many cabins: Check power_lines table populated
- If distance = 0 for all: Check geometry CRS (should be EPSG:4326)
- If performance very slow: Verify spatial indexes exist, check batch size

---

### Phase 5: Scoring Application (5-10 minutes)

**Objective**: Apply weighted scoring formula to generate weak_grid_score (0-100)

**Command**:
```bash
./scripts/15_apply_scoring.sh
```

**What It Does**:

#### Step 1: Normalize Each Metric (0-100 scale)
1. **Distance Score** (0-100):
   - 0-100m → 0 points (excellent grid)
   - 100-500m → 0-50 points (linear)
   - 500-2000m → 50-90 points (linear)
   - 2000m+ → 100 points (very weak grid)

2. **Density Score** (0-100):
   - 10+ lines → 0 points (excellent infrastructure)
   - 6-10 lines → 20 points
   - 3-5 lines → 50 points
   - 1-2 lines → 80 points
   - 0 lines → 100 points (isolated)

3. **KILE Score** (0-100):
   - 0-500 NOK → 0 points (reliable)
   - 500-1500 NOK → 0-50 points (linear)
   - 1500-3000 NOK → 50-80 points (linear)
   - 3000+ NOK → 100 points (unreliable)

4. **Voltage Score** (0-100):
   - 132 kV+ → 0 points (strong transmission)
   - 33-66 kV → 50 points (regional)
   - 22 kV or lower → 100 points (weak distribution)

5. **Age Score** (0-100):
   - 0-10 years → 0 points (modern)
   - 10-20 years → 25 points
   - 20-30 years → 50 points
   - 30-40 years → 75 points
   - 40+ years → 100 points (legacy)

#### Step 2: Calculate Weighted Composite Score
```
weak_grid_score = (0.40 × score_distance) +
                  (0.25 × score_density) +
                  (0.15 × score_kile) +
                  (0.10 × score_voltage) +
                  (0.10 × score_age)
```

#### Step 3: Assign Categories
- 90-100: "Excellent Prospect (90-100)"
- 70-89: "Good Prospect (70-89)"
- 50-69: "Moderate Prospect (50-69)"
- 0-49: "Poor Prospect (0-49)"

#### Step 4: Analysis & Export
- Generates score distribution statistics
- Shows top 20 highest-scoring cabins
- Calculates metric correlations
- Exports high-value prospects (score ≥ 70) to CSV

**Expected Output**:
```
Score Distribution:
  Excellent (90-100): ~5-10% (2000-4000 cabins)
  Good (70-89): ~15-20% (5000-7000 cabins)
  Moderate (50-69): ~30-40% (11000-15000 cabins)
  Poor (0-49): ~35-45% (13000-17000 cabins)

Correlation Analysis:
  Distance vs Score: ~0.85 (strong positive - as expected)
  Density vs Score: ~-0.60 (negative - more lines = lower score)
  Age vs Score: ~0.35 (moderate positive)
  KILE vs Score: ~0.25 (weak positive - validation metric)

Export: data/high_value_prospects.csv (~7000-11000 cabins)
```

**Validation**:
```bash
# Check score distribution
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT score_category, COUNT(*), ROUND(AVG(weak_grid_score), 1) as avg_score
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY score_category
ORDER BY avg_score DESC;"

# Verify CSV export
head -20 data/high_value_prospects.csv
wc -l data/high_value_prospects.csv
```

---

### Phase 6: Validation & Quality Checks (5 minutes)

**Objective**: Verify scoring accuracy and identify any data quality issues

**Commands**:
```bash
# 1. Check for anomalies (cabins with extreme scores)
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT id, postal_code, distance_to_line_m, grid_density_lines_1km,
       weak_grid_score, score_category
FROM cabins
WHERE weak_grid_score > 95
ORDER BY weak_grid_score DESC LIMIT 10;"

# 2. Verify geographic clustering (high scores should be in remote areas)
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT LEFT(postal_code, 2) as region,
       COUNT(*) FILTER (WHERE weak_grid_score >= 90) as excellent,
       COUNT(*) as total
FROM cabins
GROUP BY LEFT(postal_code, 2)
ORDER BY COUNT(*) FILTER (WHERE weak_grid_score >= 90) DESC
LIMIT 10;"

# 3. Manual spot-check: Pick 3 high-scoring cabins and verify on map
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT id, ST_X(geometry) as lon, ST_Y(geometry) as lat,
       distance_to_line_m, weak_grid_score
FROM cabins
WHERE weak_grid_score >= 90
ORDER BY RANDOM() LIMIT 3;"
# Copy lon/lat to Google Maps to verify they're in remote mountain areas

# 4. Data quality summary
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT * FROM data_quality_summary;"
```

**Expected Validation Results**:
- ✓ High scores (90+) are remote mountain cabins with distance >1000m
- ✓ Low scores (0-30) are cabins near dense grid infrastructure
- ✓ Geographic clustering: High scores in inland mountain regions, low scores near coast/cities
- ✓ Correlation checks: Distance is strongest predictor (r > 0.8)

**Red Flags to Investigate**:
- ✗ High score but distance <200m (scoring error)
- ✗ Low score but distance >2000m (formula issue)
- ✗ All cabins in one region have same score (data quality problem)
- ✗ Correlation(distance, score) < 0.5 (weights may be wrong)

---

## Parallelization Opportunities

### During Implementation

| Operation | Can Parallelize? | Method | Speedup |
|-----------|------------------|--------|---------|
| Download 4 layers | ✅ YES | Background processes (`&`) | 75% (15 min vs 60 min) |
| Load 4 tables | ❌ NO | Sequential (schema dependencies) | N/A |
| Calculate metrics | ⚠️ PARTIAL | Batched internally (1000 cabins/batch) | N/A |
| Apply scoring | ❌ NO | Single UPDATE statements | N/A |

### Internal Batching (Automated)

The metrics calculation script (`14_calculate_metrics.sh`) **automatically** processes cabins in batches of 1000 to avoid memory issues and enable progress monitoring. This is not user-configurable but provides significant performance benefits:

- Prevents out-of-memory errors with large datasets
- Enables progress tracking (shows "Batch 15/38...")
- Allows graceful recovery from interruptions
- Learned from `scripts/11_assign_by_batch.sh` performance issues

---

## Performance Considerations

### Expected Execution Times

| Component | Time Estimate | Bottleneck |
|-----------|---------------|------------|
| Schema creation | 30 sec | Disk I/O (indexes) |
| Data download | 10-15 min | Network bandwidth |
| Data load | 15-20 min | ogr2ogr parsing, spatial indexing |
| Distance calc | 20-30 min | Nearest-neighbor queries (37K × spatial index lookup) |
| Density calc | 20-30 min | ST_DWithin radius queries (37K × 1km buffer) |
| Age calc | 10-15 min | Aggregation queries |
| Scoring | 5-10 min | UPDATE statements with CASE expressions |

**Total**: 100-145 minutes (1.7-2.4 hours)

### Performance Optimizations Applied

1. **Spatial Indexes**: GIST indexes on all geometry columns
2. **Batch Processing**: 1000 cabins per batch prevents memory exhaustion
3. **Lateral Joins**: Used for efficient nearest-neighbor queries
4. **Geography Mode**: ST_Distance uses accurate Haversine distance (meters)
5. **Parallel Downloads**: 4 simultaneous API requests instead of sequential
6. **Materialized Views**: Pre-computed analytics for fast querying

### If Performance is Too Slow

**Option 1: Increase Batch Size**
```bash
# Edit scripts/14_calculate_metrics.sh
BATCH_SIZE=2000  # Instead of 1000
```
Trade-off: Faster, but uses more memory

**Option 2: Process Subset First**
```bash
# Test on 5000 cabins first
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
DELETE FROM cabins WHERE id > 5000;"
# Run full pipeline, verify results, then reload all cabins
```

**Option 3: Use Spatial Partitioning**
```bash
# Process by postal code prefix in parallel
# Requires script modifications
```

---

## Validation Criteria

### Phase 1: Schema Setup
✅ Tables exist: `power_lines`, `power_poles`, `cables`, `transformers`
✅ Indexes created: Check `\d power_lines` shows GIST index
✅ Functions exist: `calculate_weak_grid_score()`, `refresh_grid_analytics()`
✅ New columns in cabins: `weak_grid_score`, `distance_to_line_m`, etc.

### Phase 2: Data Download
✅ 4 GeoJSON files in `data/nve_infrastructure/`
✅ File sizes >100 KB each
✅ Valid GeoJSON: `grep '"type":"FeatureCollection"' *.geojson` succeeds
✅ Feature counts >0 for all layers

### Phase 3: Data Load
✅ Row counts: power_lines >1000, power_poles >3000, cables >200, transformers >50
✅ No NULL geometries: `SELECT COUNT(*) FROM power_lines WHERE geometry IS NULL;` returns 0
✅ Valid owner codes: `SELECT COUNT(DISTINCT owner_orgnr) FROM power_lines;` returns 10-30
✅ Reasonable voltage levels: 22 kV, 33 kV, 66 kV, 132 kV present

### Phase 4: Metrics Calculation
✅ Completeness: 100% of cabins have distance_to_line_m
✅ Completeness: 100% of cabins have grid_density_lines_1km
✅ Completeness: >90% of cabins have grid_age_years
✅ Distance range: min ~0m, max >1000m, median 200-500m
✅ Density range: min 0, max >10, median 2-4 lines
✅ Age range: min 0, max 60+, median 20-30 years

### Phase 5: Scoring
✅ Completeness: 100% of cabins with distance have weak_grid_score
✅ Score range: 0-100 (no values outside this range)
✅ Category distribution: ~5-10% Excellent, ~15-20% Good, ~30-40% Moderate, ~35-45% Poor
✅ Correlation: distance vs score correlation >0.7 (strong positive)
✅ Export: CSV file created with 5000-10000 rows (score ≥70)

### Phase 6: Quality Checks
✅ High scores are remote cabins: Manually verify 3 random cabins with score >90
✅ Low scores are urban cabins: Manually verify 3 random cabins with score <30
✅ Geographic clustering makes sense: Inland mountain areas have higher scores
✅ No anomalies: No cabins with score >90 and distance <200m

---

## Troubleshooting Guide

### Problem: Downloads fail with 404 or timeout
**Cause**: NVE API down or layer IDs changed
**Solution**:
1. Check NVE API status: Visit https://gis3.nve.no/arcgis/rest/services/Publikum/Distribusjonsnettanlegg/MapServer
2. Verify layer IDs: Layer 2 = Distribusjonsnett, Layer 4 = Master og stolper, etc.
3. Adjust bounding box if Agder coords wrong: Current: (6.5, 57.8) to (9.2, 59.5)

### Problem: ogr2ogr fails during load
**Cause**: Invalid GeoJSON or missing PostGIS extensions
**Solution**:
1. Validate GeoJSON: `cat data/nve_infrastructure/power_lines.geojson | jq .`
2. Check PostGIS: `docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT PostGIS_Version();"`
3. Re-download file if corrupted

### Problem: Metrics calculation extremely slow (>3 hours)
**Cause**: Missing spatial indexes or inefficient queries
**Solution**:
1. Verify indexes: `\d power_lines` should show GIST index on geometry
2. Check query plan: `EXPLAIN ANALYZE SELECT ... FROM cabins ... LIMIT 1;`
3. Increase batch size to 2000 or 5000
4. Process smaller subset first (e.g., 10,000 cabins) to test

### Problem: Scores all 0 or all 100
**Cause**: Normalization formula error or missing data
**Solution**:
1. Check raw metrics: `SELECT distance_to_line_m, grid_density_lines_1km FROM cabins LIMIT 100;`
2. Verify KILE costs loaded: `SELECT COUNT(*) FROM grid_companies WHERE kile_cost_nok IS NOT NULL;`
3. Review scoring formula in `15_apply_scoring.sh`

### Problem: High correlation between KILE and score expected but not found
**Cause**: KILE is a VALIDATION metric (15% weight), not primary driver
**Solution**: This is expected. Distance (40% weight) should be strongest correlation (r > 0.8). KILE correlation may be weak (r ~ 0.2-0.4) because it measures reliability at company level, not cabin-specific grid weakness.

---

## Next Steps After Implementation

### 1. Business Analysis
- Review `data/high_value_prospects.csv` for top 500 cabins
- Cross-reference with road access data (if available)
- Prioritize cabins in clusters (multiple weak grid cabins nearby = economies of scale)
- Filter by business constraints (e.g., exclude cabins <20m² floor area)

### 2. Visualization
- Load PostGIS data into QGIS
- Create heat map of weak_grid_score
- Overlay with grid infrastructure (power lines, transformers)
- Identify geographic patterns and opportunity clusters

### 3. Refinement
- Tune weights based on field validation (e.g., if distance proves more/less important)
- Add seasonal factors (winter outage risk)
- Incorporate elevation data (higher elevation = more weather exposure)
- Add historical outage data if available from grid companies

### 4. Automation
- Schedule weekly/monthly refreshes (NVE data may update)
- Set up alerts for new high-value prospects
- Integrate with CRM system for sales pipeline

---

## Success Criteria

**Minimum Viable Success**:
- ✅ All 37,170 cabins have weak_grid_score calculated
- ✅ Score distribution is reasonable (not all 0 or all 100)
- ✅ Distance is strong predictor of score (correlation >0.7)
- ✅ 5,000-10,000 cabins identified as Good or Excellent prospects

**Full Success**:
- ✅ All validation checks pass
- ✅ Spot-check of 10 high-scoring cabins confirms they're remote/weak grid
- ✅ Spot-check of 10 low-scoring cabins confirms they're urban/strong grid
- ✅ Geographic clustering makes business sense
- ✅ CSV export is actionable for sales team

**Excellence**:
- ✅ Correlations match theoretical expectations (distance > density > age > KILE)
- ✅ Score distribution matches known grid quality patterns in Norway
- ✅ System runs in <2 hours total execution time
- ✅ Documentation enables non-technical stakeholders to understand scoring

---

## Appendix: Command Reference

### Full Execution Sequence
```bash
# Navigate to project
cd /home/klaus/klauspython/svakenett

# Phase 1: Schema
docker exec svakenett-postgis psql -U postgres -d svakenett < docs/DATABASE_SCHEMA.sql

# Phase 2: Download (parallel)
./scripts/12_download_grid_infrastructure.sh

# Phase 3: Load & Transform
./scripts/13_load_grid_infrastructure.sh

# Phase 4: Calculate Metrics (60-90 min)
./scripts/14_calculate_metrics.sh

# Phase 5: Apply Scoring
./scripts/15_apply_scoring.sh

# Phase 6: Validate
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT score_category, COUNT(*)
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY score_category;"
```

### Useful Queries During Implementation
```sql
-- Check progress during metrics calculation
SELECT COUNT(*) FILTER (WHERE distance_to_line_m IS NOT NULL) as done,
       COUNT(*) as total,
       ROUND(100.0 * COUNT(*) FILTER (WHERE distance_to_line_m IS NOT NULL) / COUNT(*), 1) as pct
FROM cabins;

-- Top 10 weakest grid cabins
SELECT id, postal_code, distance_to_line_m, weak_grid_score
FROM cabins
ORDER BY weak_grid_score DESC LIMIT 10;

-- Score distribution histogram
SELECT
    WIDTH_BUCKET(weak_grid_score, 0, 100, 10) * 10 as score_bucket,
    COUNT(*) as cabin_count
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Grid company comparison
SELECT gc.company_name, COUNT(c.id) as cabins,
       ROUND(AVG(c.weak_grid_score), 1) as avg_score
FROM grid_companies gc
JOIN cabins c ON gc.company_code = c.grid_company_code
GROUP BY gc.company_name
ORDER BY AVG(c.weak_grid_score) DESC
LIMIT 15;
```

---

**Document Version**: 1.0
**Last Updated**: 2025-11-22
**Estimated Total Time**: 100-145 minutes
**Complexity**: Medium (batch processing, spatial queries, data transformation)
