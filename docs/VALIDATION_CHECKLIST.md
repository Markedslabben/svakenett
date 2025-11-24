# Grid Infrastructure Scoring System - Validation Checklist

Use this checklist to verify each phase of implementation and ensure data quality throughout the process.

---

## Pre-Implementation Checks

### Environment Verification
- [ ] Docker container `svakenett-postgis` is running
  ```bash
  docker ps | grep svakenett-postgis
  ```
- [ ] PostgreSQL accessible on localhost:5432
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT version();"
  ```
- [ ] PostGIS extension enabled
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT PostGIS_Version();"
  ```
- [ ] 37,170 cabins loaded in database
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins;"
  # Expected: 37170
  ```
- [ ] 84 grid companies loaded with KILE costs
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM grid_companies WHERE kile_cost_nok IS NOT NULL;"
  # Expected: 84
  ```

---

## Phase 1: Schema Setup

### Schema Creation
- [ ] Script executed without errors
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett < docs/DATABASE_SCHEMA.sql
  ```

### Table Verification
- [ ] `power_lines` table exists
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d power_lines"
  ```
- [ ] `power_poles` table exists
- [ ] `cables` table exists
- [ ] `transformers` table exists

### Cabins Table Enhancements
- [ ] New columns added to `cabins` table
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d cabins" | grep -E "distance_to_line_m|weak_grid_score|score_category"
  # Should see: distance_to_line_m, grid_density_lines_1km, grid_age_years,
  #             voltage_level_kv, score_distance, score_density, score_kile,
  #             score_voltage, score_age, weak_grid_score, score_category
  ```

### Index Verification
- [ ] Spatial indexes created on geometry columns
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d power_lines" | grep GIST
  # Should see: idx_power_lines_geom GIST (geometry)
  ```
- [ ] Scoring indexes created on cabins table
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\d cabins" | grep "idx_cabins_weak_grid_score"
  ```

### Function Verification
- [ ] `calculate_weak_grid_score()` function exists
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\df calculate_weak_grid_score"
  ```
- [ ] `refresh_grid_analytics()` function exists
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "\df refresh_grid_analytics"
  ```

---

## Phase 2: Data Download

### Download Execution
- [ ] Script executed without errors
  ```bash
  ./scripts/12_download_grid_infrastructure.sh
  ```
- [ ] All 4 downloads completed successfully (check script output for "✓ Downloaded")

### File Verification
- [ ] `data/nve_infrastructure/power_lines.geojson` exists and >100 KB
  ```bash
  ls -lh data/nve_infrastructure/power_lines.geojson
  ```
- [ ] `data/nve_infrastructure/power_poles.geojson` exists and >100 KB
- [ ] `data/nve_infrastructure/cables.geojson` exists and >50 KB
- [ ] `data/nve_infrastructure/transformers.geojson` exists and >20 KB

### GeoJSON Validity
- [ ] All files are valid GeoJSON (contain "FeatureCollection")
  ```bash
  grep '"type":"FeatureCollection"' data/nve_infrastructure/*.geojson
  # All 4 files should match
  ```
- [ ] Feature counts are reasonable
  ```bash
  grep -o '"type":"Feature"' data/nve_infrastructure/power_lines.geojson | wc -l
  # Expected: 1000-10000 features

  grep -o '"type":"Feature"' data/nve_infrastructure/power_poles.geojson | wc -l
  # Expected: 3000-20000 features

  grep -o '"type":"Feature"' data/nve_infrastructure/cables.geojson | wc -l
  # Expected: 200-2000 features

  grep -o '"type":"Feature"' data/nve_infrastructure/transformers.geojson | wc -l
  # Expected: 50-1000 features
  ```

---

## Phase 3: Data Load & Transform

### Load Execution
- [ ] Script executed without errors
  ```bash
  ./scripts/13_load_grid_infrastructure.sh
  ```

### Row Count Verification
- [ ] `power_lines` table populated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM power_lines;"
  # Expected: >1000 rows
  ```
- [ ] `power_poles` table populated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM power_poles;"
  # Expected: >3000 rows
  ```
- [ ] `cables` table populated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cables;"
  # Expected: >200 rows
  ```
- [ ] `transformers` table populated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM transformers;"
  # Expected: >50 rows
  ```

### Data Quality Checks
- [ ] No NULL geometries in power_lines
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM power_lines WHERE geometry IS NULL;"
  # Expected: 0
  ```
- [ ] Voltage levels are reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT DISTINCT voltage_kv FROM power_lines ORDER BY voltage_kv;"
  # Expected: 22, 33, 66, 132, 300 (or similar values)
  ```
- [ ] Owner organization numbers exist
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(DISTINCT owner_orgnr) FROM power_lines WHERE owner_orgnr IS NOT NULL;"
  # Expected: 10-50 unique owners
  ```
- [ ] Year_built values are valid
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(year_built), MAX(year_built) FROM power_lines WHERE year_built IS NOT NULL;"
  # Expected: MIN around 1960-1980, MAX around 2020-2024
  ```
- [ ] Average grid age is reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT ROUND(AVG(2025 - year_built), 1) as avg_age FROM power_lines WHERE year_built IS NOT NULL;"
  # Expected: 20-35 years
  ```

### Spatial Data Verification
- [ ] Power lines have valid LineString geometries
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM power_lines WHERE ST_GeometryType(geometry) = 'ST_LineString';"
  # Should equal total row count
  ```
- [ ] Power poles have valid Point geometries
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM power_poles WHERE ST_GeometryType(geometry) = 'ST_Point';"
  # Should equal total row count
  ```
- [ ] All geometries are in EPSG:4326 (WGS84)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT DISTINCT ST_SRID(geometry) FROM power_lines;"
  # Expected: 4326
  ```

---

## Phase 4: Metrics Calculation

### Execution Monitoring
- [ ] Script started without errors
  ```bash
  ./scripts/14_calculate_metrics.sh
  ```
- [ ] Progress indicators showing batch numbers (e.g., "Batch 15/38...")
- [ ] No SQL errors in output

### Metric 1: Distance to Power Line
- [ ] All cabins have distance calculated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE distance_to_line_m IS NOT NULL;"
  # Expected: 37170 (100%)
  ```
- [ ] Distance values are reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(distance_to_line_m) as min, ROUND(AVG(distance_to_line_m), 0) as avg, MAX(distance_to_line_m) as max FROM cabins WHERE distance_to_line_m IS NOT NULL;"
  # Expected: MIN ~0-50m, AVG ~300-800m, MAX >2000m
  ```
- [ ] Voltage levels captured
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE voltage_level_kv IS NOT NULL;"
  # Expected: 37170 (100%)
  ```

### Metric 2: Grid Density
- [ ] All cabins have density calculated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE grid_density_lines_1km IS NOT NULL;"
  # Expected: 37170 (100%)
  ```
- [ ] Density values are reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(grid_density_lines_1km) as min, ROUND(AVG(grid_density_lines_1km), 1) as avg, MAX(grid_density_lines_1km) as max FROM cabins;"
  # Expected: MIN 0, AVG 2-5, MAX >20
  ```
- [ ] Some cabins have 0 density (isolated locations)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE grid_density_lines_1km = 0;"
  # Expected: >100 (remote mountain cabins)
  ```

### Metric 3: Grid Age
- [ ] Most cabins have age calculated (>90%)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE grid_age_years IS NOT NULL;"
  # Expected: >33000 (>90% of 37170)
  ```
- [ ] Age values are reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(grid_age_years) as min, ROUND(AVG(grid_age_years), 1) as avg, MAX(grid_age_years) as max FROM cabins WHERE grid_age_years IS NOT NULL;"
  # Expected: MIN 0-5, AVG 20-35, MAX 50-70
  ```

### Metric 4: Transformer Distance
- [ ] All cabins have transformer distance
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE distance_to_transformer_m IS NOT NULL;"
  # Expected: 37170 (100%)
  ```

### Statistical Validation
- [ ] Distance distribution looks like right-skewed normal
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY distance_to_line_m) as q25, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_to_line_m) as median, PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY distance_to_line_m) as q75 FROM cabins;"
  # Expected: Q25 ~100-200m, Median ~300-500m, Q75 ~600-1000m
  ```

---

## Phase 5: Scoring Application

### Execution
- [ ] Script executed without errors
  ```bash
  ./scripts/15_apply_scoring.sh
  ```

### Normalized Scores
- [ ] All 5 component scores calculated
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE score_distance IS NOT NULL AND score_density IS NOT NULL AND score_kile IS NOT NULL AND score_voltage IS NOT NULL AND score_age IS NOT NULL;"
  # Expected: Close to 37170 (some may lack KILE if no company assigned)
  ```
- [ ] Component scores are 0-100
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(score_distance) as min, MAX(score_distance) as max FROM cabins WHERE score_distance IS NOT NULL;"
  # Expected: MIN ~0, MAX ~100
  ```

### Composite Score
- [ ] All cabins with distance have composite score
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE weak_grid_score IS NOT NULL;"
  # Expected: 37170 or very close
  ```
- [ ] Composite scores are 0-100
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT MIN(weak_grid_score) as min, MAX(weak_grid_score) as max FROM cabins WHERE weak_grid_score IS NOT NULL;"
  # Expected: MIN ~0-10, MAX ~95-100
  ```

### Score Distribution
- [ ] Score distribution is reasonable
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT score_category, COUNT(*), ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct FROM cabins WHERE weak_grid_score IS NOT NULL GROUP BY score_category ORDER BY MIN(weak_grid_score) DESC;"
  # Expected distribution:
  # Excellent (90-100):  5-10%
  # Good (70-89):       15-20%
  # Moderate (50-69):   30-40%
  # Poor (0-49):        35-45%
  ```

### Correlation Analysis
- [ ] Distance has strong positive correlation (r > 0.7)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT ROUND(CORR(distance_to_line_m, weak_grid_score)::numeric, 3) as correlation FROM cabins WHERE weak_grid_score IS NOT NULL;"
  # Expected: >0.70 (strong positive)
  ```
- [ ] Density has negative correlation
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT ROUND(CORR(grid_density_lines_1km, weak_grid_score)::numeric, 3) as correlation FROM cabins WHERE weak_grid_score IS NOT NULL;"
  # Expected: <0 (negative - more lines = lower score)
  ```

### CSV Export
- [ ] High-value prospects CSV created
  ```bash
  ls -lh data/high_value_prospects.csv
  # Should exist and be >100 KB
  ```
- [ ] CSV has header row
  ```bash
  head -1 data/high_value_prospects.csv
  # Should see: id,postal_code,grid_company,kile_cost_nok,distance_to_line_m,...
  ```
- [ ] CSV has 5000-11000 rows (score ≥70)
  ```bash
  wc -l data/high_value_prospects.csv
  # Expected: 5001-11001 (including header)
  ```

---

## Phase 6: Manual Validation

### High Score Spot-Checks (Score ≥90)
- [ ] Sample 5 high-scoring cabins
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT id, postal_code, distance_to_line_m, grid_density_lines_1km, weak_grid_score, ST_X(geometry) as lon, ST_Y(geometry) as lat FROM cabins WHERE weak_grid_score >= 90 ORDER BY RANDOM() LIMIT 5;"
  ```
- [ ] Verify on Google Maps (paste lon/lat coordinates)
  - [ ] Cabin 1: Located in remote mountain area? (Yes/No)
  - [ ] Cabin 2: Located in remote mountain area? (Yes/No)
  - [ ] Cabin 3: Located in remote mountain area? (Yes/No)
  - [ ] Cabin 4: Located in remote mountain area? (Yes/No)
  - [ ] Cabin 5: Located in remote mountain area? (Yes/No)

### Low Score Spot-Checks (Score ≤30)
- [ ] Sample 5 low-scoring cabins
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT id, postal_code, distance_to_line_m, grid_density_lines_1km, weak_grid_score, ST_X(geometry) as lon, ST_Y(geometry) as lat FROM cabins WHERE weak_grid_score <= 30 ORDER BY RANDOM() LIMIT 5;"
  ```
- [ ] Verify on Google Maps
  - [ ] Cabin 1: Located near urban area or valley? (Yes/No)
  - [ ] Cabin 2: Located near urban area or valley? (Yes/No)
  - [ ] Cabin 3: Located near urban area or valley? (Yes/No)
  - [ ] Cabin 4: Located near urban area or valley? (Yes/No)
  - [ ] Cabin 5: Located near urban area or valley? (Yes/No)

### Geographic Clustering
- [ ] High scores cluster in expected regions
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT LEFT(postal_code, 2) as region, COUNT(*) FILTER (WHERE weak_grid_score >= 90) as excellent, COUNT(*) as total, ROUND(AVG(weak_grid_score), 1) as avg_score FROM cabins WHERE weak_grid_score IS NOT NULL GROUP BY LEFT(postal_code, 2) ORDER BY COUNT(*) FILTER (WHERE weak_grid_score >= 90) DESC LIMIT 10;"
  # Check if inland mountain regions (e.g., Setesdal, Sirdal) have higher scores than coastal regions
  ```

### Anomaly Detection
- [ ] No cabins with score >90 but distance <200m
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE weak_grid_score > 90 AND distance_to_line_m < 200;"
  # Expected: 0 (would indicate scoring error)
  ```
- [ ] No cabins with score <10 but distance >2000m
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT COUNT(*) FROM cabins WHERE weak_grid_score < 10 AND distance_to_line_m > 2000;"
  # Expected: 0 (would indicate scoring error)
  ```

---

## Data Quality Summary

### Run Full Quality Report
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT * FROM data_quality_summary;"
```

Expected output:
- [ ] `power_lines`: No NULL geometries, <5% NULL voltage, <10% NULL year
- [ ] `cabins`: No NULL geometries, 0 NULL scores, 0 NULL distances, <2% NULL company
- [ ] `transformers`: No NULL geometries, <20% NULL capacity

---

## Performance Validation

### Execution Times
- [ ] Schema setup: <5 minutes
- [ ] Data download: 10-20 minutes (depends on network)
- [ ] Data load: 15-25 minutes
- [ ] Metrics calculation: 60-120 minutes (37K cabins)
- [ ] Scoring: 5-15 minutes
- [ ] **Total**: <3 hours

### Query Performance
- [ ] Simple score lookup is fast (<100ms)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "EXPLAIN ANALYZE SELECT * FROM cabins WHERE weak_grid_score >= 90 LIMIT 100;"
  # Execution time should be <100ms
  ```
- [ ] Materialized views refresh quickly (<5 min)
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT refresh_grid_analytics();"
  # Should complete in <5 minutes
  ```

---

## Business Validation

### Top Prospects Review
- [ ] Review top 20 highest-scoring cabins
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT id, postal_code, distance_to_line_m, grid_density_lines_1km, grid_age_years, weak_grid_score FROM cabins WHERE weak_grid_score IS NOT NULL ORDER BY weak_grid_score DESC LIMIT 20;"
  ```
  - [ ] Distances are all >1000m? (Expected: Yes)
  - [ ] Densities are 0-2 lines? (Expected: Mostly yes)
  - [ ] Ages are >30 years? (Expected: Mostly yes)

### Grid Company Comparison
- [ ] Companies with high KILE have higher average scores
  ```bash
  docker exec svakenett-postgis psql -U postgres -d svakenett -c "SELECT gc.company_name, gc.kile_cost_nok, COUNT(c.id) as cabins, ROUND(AVG(c.weak_grid_score), 1) as avg_score FROM grid_companies gc JOIN cabins c ON gc.company_code = c.grid_company_code WHERE c.weak_grid_score IS NOT NULL GROUP BY gc.company_name, gc.kile_cost_nok HAVING COUNT(c.id) >= 10 ORDER BY gc.kile_cost_nok DESC LIMIT 10;"
  # Companies with KILE >2000 should have avg_score >55
  ```

---

## Final Sign-Off

### System Readiness
- [ ] All 37,170 cabins have weak_grid_score
- [ ] Score distribution is reasonable (not all 0 or 100)
- [ ] Distance correlation >0.70 (strong positive)
- [ ] Manual spot-checks confirm scoring accuracy (10/10 correct)
- [ ] No critical anomalies detected
- [ ] CSV export has 5000-10000 high-value prospects
- [ ] Total execution time <3 hours

### Documentation Completeness
- [ ] SCORING_ALGORITHM_DESIGN.md reviewed
- [ ] DATABASE_SCHEMA.sql validated
- [ ] IMPLEMENTATION_PLAN.md followed
- [ ] APPROACH_COMPARISON.md understood
- [ ] GRID_INFRASTRUCTURE_SCORING_README.md read

### Handoff Readiness
- [ ] Sales team can access `data/high_value_prospects.csv`
- [ ] Explanation prepared for scoring methodology
- [ ] Sample cabin-specific talking points created
- [ ] Next steps defined (visualization, CRM import, campaign launch)

---

## Rollback Plan (If Validation Fails)

### Partial Rollback: Remove Scoring Only
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett <<'SQL'
UPDATE cabins SET
  score_distance = NULL,
  score_density = NULL,
  score_kile = NULL,
  score_voltage = NULL,
  score_age = NULL,
  weak_grid_score = NULL,
  score_category = NULL,
  scoring_updated_at = NULL;
SQL
```
Then re-run `15_apply_scoring.sh` after fixing formula.

### Full Rollback: Remove All Grid Data
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett <<'SQL'
DROP TABLE IF EXISTS power_lines CASCADE;
DROP TABLE IF EXISTS power_poles CASCADE;
DROP TABLE IF EXISTS cables CASCADE;
DROP TABLE IF EXISTS transformers CASCADE;
DROP MATERIALIZED VIEW IF EXISTS grid_company_infrastructure_stats;
DROP MATERIALIZED VIEW IF EXISTS high_value_prospects;

ALTER TABLE cabins
  DROP COLUMN IF EXISTS distance_to_line_m,
  DROP COLUMN IF EXISTS distance_to_transformer_m,
  DROP COLUMN IF EXISTS grid_density_lines_1km,
  DROP COLUMN IF EXISTS grid_density_length_km,
  DROP COLUMN IF EXISTS grid_age_years,
  DROP COLUMN IF EXISTS voltage_level_kv,
  DROP COLUMN IF EXISTS nearest_line_owner,
  DROP COLUMN IF EXISTS score_distance,
  DROP COLUMN IF EXISTS score_density,
  DROP COLUMN IF EXISTS score_kile,
  DROP COLUMN IF EXISTS score_voltage,
  DROP COLUMN IF EXISTS score_age,
  DROP COLUMN IF EXISTS weak_grid_score,
  DROP COLUMN IF EXISTS score_category,
  DROP COLUMN IF EXISTS scoring_updated_at;
SQL
```
Then restart from Phase 1.

---

**Validation Completed By**: _______________
**Date**: _______________
**Outcome**: ☐ PASS ☐ FAIL (describe issues)
**Notes**: _______________________________________________

