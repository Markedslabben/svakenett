# Grid Infrastructure Scoring - Quick Start

## 5-Minute Overview

**What**: Score 37,170 Norwegian mountain cabins on grid weakness (0-100 scale)
**Why**: Identify battery system prospects with data-driven precision
**How**: Analyze actual grid infrastructure (power lines, poles, transformers)
**Output**: 7,000-10,000 high-value prospects exported to CSV

---

## One-Command Execution

```bash
# Full pipeline (2-3 hours)
cd /home/klaus/klauspython/svakenett && \
docker exec svakenett-postgis psql -U postgres -d svakenett < docs/DATABASE_SCHEMA.sql && \
./scripts/12_download_grid_infrastructure.sh && \
./scripts/13_load_grid_infrastructure.sh && \
./scripts/14_calculate_metrics.sh && \
./scripts/15_apply_scoring.sh
```

---

## Step-by-Step Execution

### 1. Create Database Schema (5 min)
```bash
docker exec svakenett-postgis psql -U postgres -d svakenett < docs/DATABASE_SCHEMA.sql
```
Creates: 4 tables (power_lines, power_poles, cables, transformers) + enhances cabins table

### 2. Download Grid Data (10-15 min, parallel)
```bash
./scripts/12_download_grid_infrastructure.sh
```
Downloads: 4 NVE layers simultaneously → `data/nve_infrastructure/*.geojson`

### 3. Load to Database (15-20 min)
```bash
./scripts/13_load_grid_infrastructure.sh
```
Loads: GeoJSON → PostGIS with transformation and spatial indexing

### 4. Calculate Metrics (60-90 min, batched)
```bash
./scripts/14_calculate_metrics.sh
```
Calculates: Distance, density, age, voltage for all 37,170 cabins (1000/batch)

### 5. Apply Scoring (5-10 min)
```bash
./scripts/15_apply_scoring.sh
```
Generates: weak_grid_score (0-100), categories, exports CSV

---

## Validation (2 min)

```bash
# Check score distribution
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT score_category, COUNT(*)
FROM cabins WHERE weak_grid_score IS NOT NULL
GROUP BY score_category ORDER BY MIN(weak_grid_score) DESC;"

# View top 10 prospects
head -20 data/high_value_prospects.csv
```

---

## Key Files

### Documentation
- **SCORING_ALGORITHM_DESIGN.md**: Algorithm spec (5 metrics, weights, rationale)
- **DATABASE_SCHEMA.sql**: Complete DDL (tables, indexes, views, functions)
- **IMPLEMENTATION_PLAN.md**: Detailed execution guide with troubleshooting
- **APPROACH_COMPARISON.md**: Old vs New approach analysis
- **VALIDATION_CHECKLIST.md**: Phase-by-phase verification steps
- **DELIVERABLES_SUMMARY.md**: Complete project summary

### Scripts
- **12_download_grid_infrastructure.sh**: Parallel download (4 NVE layers)
- **13_load_grid_infrastructure.sh**: GeoJSON → PostGIS transformation
- **14_calculate_metrics.sh**: Batch metrics calculation (1000 cabins/batch)
- **15_apply_scoring.sh**: Weighted scoring + CSV export

---

## Scoring Formula

```
weak_grid_score = (0.40 × distance_score) +
                  (0.25 × density_score) +
                  (0.15 × kile_score) +
                  (0.10 × voltage_score) +
                  (0.10 × age_score)

Higher score = Weaker grid = Better prospect
```

### Score Categories
- **90-100**: Excellent Prospect (remote, isolated grid)
- **70-89**: Good Prospect (weak infrastructure)
- **50-69**: Moderate Prospect (marginal grid)
- **0-49**: Poor Prospect (strong grid, not actionable)

---

## Expected Results

### Score Distribution
```
Excellent (90-100):  2,500 cabins  (6.7%)  ← HIGH PRIORITY
Good (70-89):        6,000 cabins  (16.1%) ← MEDIUM PRIORITY
Moderate (50-69):   13,000 cabins  (35.0%)
Poor (0-49):        15,670 cabins  (42.2%)
```

### CSV Export
**File**: `data/high_value_prospects.csv`
**Rows**: 7,000-10,000 (score ≥70)
**Columns**: id, postal_code, grid_company, distance_m, density, age, voltage, score, lat/lon

---

## Troubleshooting

### Downloads fail
**Fix**: Check NVE API status at https://gis3.nve.no/arcgis/rest/services/

### Metrics calculation slow (>3 hours)
**Fix**: Increase batch size in `14_calculate_metrics.sh` (line 11: `BATCH_SIZE=2000`)

### Scores all 0 or 100
**Fix**: Check power_lines table populated: `SELECT COUNT(*) FROM power_lines;` (expect >1000)

---

## Quick Validation Commands

```bash
# Check infrastructure loaded
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT 'power_lines' as table, COUNT(*) FROM power_lines
UNION ALL SELECT 'power_poles', COUNT(*) FROM power_poles
UNION ALL SELECT 'cables', COUNT(*) FROM cables
UNION ALL SELECT 'transformers', COUNT(*) FROM transformers;"

# Check all cabins scored
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT COUNT(*) as total, COUNT(weak_grid_score) as scored
FROM cabins;"

# Check correlation (should be >0.7)
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT ROUND(CORR(distance_to_line_m, weak_grid_score)::numeric, 3)
FROM cabins WHERE weak_grid_score IS NOT NULL;"
```

---

## Next Steps After Execution

1. **Review CSV**: Open `data/high_value_prospects.csv` in Excel/spreadsheet
2. **Spot-Check**: Pick 5 high-scoring cabins, verify locations on Google Maps
3. **Visualize**: Load PostGIS data into QGIS for heat map
4. **Sales Campaign**: Import CSV to CRM, prioritize score ≥90 cabins

---

## Key Metrics

| Metric | Weight | 0 Points (Strong Grid) | 100 Points (Weak Grid) |
|--------|--------|------------------------|------------------------|
| Distance | 40% | 0-100m | 2000m+ |
| Density | 25% | 10+ lines | 0 lines |
| KILE | 15% | 0-500 NOK | 3000+ NOK |
| Voltage | 10% | 132 kV+ | 22 kV |
| Age | 10% | 0-10 years | 40+ years |

---

## Success Criteria

- ✅ All 37,170 cabins scored (100% coverage)
- ✅ Distance correlation >0.70 (strong positive)
- ✅ Score distribution reasonable (~7% Excellent, ~16% Good)
- ✅ High scores in remote mountain areas (manual validation)
- ✅ Low scores near urban/coastal areas (manual validation)
- ✅ CSV export has 7,000-10,000 prospects

---

## Time Estimate

| Phase | Time | Parallel? |
|-------|------|-----------|
| Schema | 5 min | No |
| Download | 10-15 min | Yes (4 parallel) |
| Load | 15-20 min | No |
| Metrics | 60-90 min | Batched (1000/batch) |
| Scoring | 5-10 min | No |
| **Total** | **100-145 min** | **(2-3 hours)** |

---

## Support

- **Full Documentation**: `docs/DELIVERABLES_SUMMARY.md`
- **Detailed Guide**: `docs/IMPLEMENTATION_PLAN.md`
- **Validation Steps**: `docs/VALIDATION_CHECKLIST.md`
- **Algorithm Spec**: `docs/SCORING_ALGORITHM_DESIGN.md`

---

**Status**: Ready for Execution
**Version**: 1.0
**Date**: 2025-11-22
