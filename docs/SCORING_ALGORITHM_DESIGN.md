# Grid Infrastructure-Based Scoring Algorithm

## Executive Summary

This document defines the comprehensive scoring system for identifying Norwegian mountain cabins with weak electricity grid connections as prospects for battery energy storage systems. The algorithm analyzes actual grid infrastructure data (power lines, poles, transformers) rather than approximate service area polygons.

---

## Scoring Metrics and Weights

### Primary Metrics (80% of score)

#### 1. Distance to Nearest Power Line (40%)
**Rationale**: The most direct indicator of grid weakness. Cabins far from existing power lines either have weak connections or require expensive line extensions.

**Metric Calculation**:
```sql
distance_to_line_m = ST_Distance(
    cabin.geometry::geography,
    nearest_power_line.geometry::geography
)
```

**Scoring Function**:
- 0-100m: 0 points (excellent grid access)
- 100-500m: Linear scale 0-50 points
- 500-2000m: Linear scale 50-90 points
- 2000m+: 100 points (very weak grid)

**Weight**: 40% (highest priority - direct grid weakness indicator)

---

#### 2. Grid Density Score (25%)
**Rationale**: Sparse grid infrastructure indicates weak or isolated grid connections. High density suggests robust redundancy and capacity.

**Metric Calculation**:
```sql
grid_density = COUNT(power_lines within 1000m radius) / TOTAL_AREA
line_length_km = SUM(ST_Length(power_lines within 1000m)) / 1000
```

**Scoring Function**:
- 0 lines within 1km: 100 points (isolated location)
- 1-2 lines: 80 points (minimal infrastructure)
- 3-5 lines: 50 points (moderate infrastructure)
- 6-10 lines: 20 points (good infrastructure)
- 10+ lines: 0 points (excellent infrastructure)

**Weight**: 25% (infrastructure robustness indicator)

---

#### 3. KILE Costs - Grid Reliability (15%)
**Rationale**: KILE (Quality-Adjusted Interruption Costs) represents regulatory penalties paid by utilities for outages. Higher KILE indicates less reliable grid service.

**Metric Calculation**:
```sql
kile_cost_nok = grid_company.kile_cost_nok
-- OR if using infrastructure-derived company:
kile_cost_nok = (SELECT kile_cost_nok FROM grid_companies
                 WHERE company_code = power_line.eier_orgnr)
```

**Scoring Function** (based on NVE data analysis):
- 0-500 NOK: 0 points (highly reliable)
- 500-1500 NOK: Linear scale 0-50 points
- 1500-3000 NOK: Linear scale 50-80 points
- 3000+ NOK: 100 points (unreliable grid)

**Weight**: 15% (validation metric for grid quality)

---

### Secondary Metrics (20% of score)

#### 4. Voltage Level (10%)
**Rationale**: Lower voltage lines (22 kV regional distribution) have less capacity and are more prone to voltage drops than higher voltage transmission lines.

**Metric Calculation**:
```sql
voltage_kv = nearest_power_line.spenning_kv
```

**Scoring Function**:
- 22 kV or lower: 100 points (weak distribution grid)
- 33-66 kV: 50 points (regional transmission)
- 132 kV+: 0 points (strong transmission grid)

**Weight**: 10% (capacity indicator)

---

#### 5. Grid Age (10%)
**Rationale**: Older infrastructure is more prone to failures and may not meet modern capacity demands. Age correlates with maintenance issues.

**Metric Calculation**:
```sql
avg_age_years = AVG(2025 - power_line.year)
                WHERE ST_DWithin(cabin.geometry, power_line.geometry, 1000)
```

**Scoring Function**:
- 0-10 years: 0 points (modern infrastructure)
- 10-20 years: 25 points (aging)
- 20-30 years: 50 points (old)
- 30-40 years: 75 points (very old)
- 40+ years: 100 points (legacy infrastructure)

**Weight**: 10% (reliability proxy)

---

## Composite Scoring Formula

### Mathematical Definition

```
weak_grid_score = (w₁ × S_distance) + (w₂ × S_density) + (w₃ × S_kile) +
                  (w₄ × S_voltage) + (w₅ × S_age)

where:
  w₁ = 0.40  (distance weight)
  w₂ = 0.25  (density weight)
  w₃ = 0.15  (KILE weight)
  w₄ = 0.10  (voltage weight)
  w₅ = 0.10  (age weight)

  Σ wᵢ = 1.00
```

### Score Categories

| Score Range | Category | Description | Action Priority |
|-------------|----------|-------------|----------------|
| 90-100 | Excellent Prospect | Very weak/isolated grid | High priority contact |
| 70-89 | Good Prospect | Weak grid with issues | Medium priority |
| 50-69 | Moderate Prospect | Marginal grid quality | Low priority |
| 0-49 | Poor Prospect | Strong grid connection | No action |

---

## Normalization Functions

### Distance Normalization
```python
def normalize_distance(distance_m):
    if distance_m <= 100:
        return 0
    elif distance_m <= 500:
        return (distance_m - 100) / 400 * 50
    elif distance_m <= 2000:
        return 50 + (distance_m - 500) / 1500 * 40
    else:
        return 100
```

### Density Normalization
```python
def normalize_density(line_count):
    if line_count >= 10:
        return 0
    elif line_count >= 6:
        return 20
    elif line_count >= 3:
        return 50
    elif line_count >= 1:
        return 80
    else:
        return 100
```

### KILE Normalization
```python
def normalize_kile(kile_cost):
    if kile_cost <= 500:
        return 0
    elif kile_cost <= 1500:
        return (kile_cost - 500) / 1000 * 50
    elif kile_cost <= 3000:
        return 50 + (kile_cost - 1500) / 1500 * 30
    else:
        return 100
```

### Voltage Normalization
```python
def normalize_voltage(voltage_kv):
    if voltage_kv >= 132:
        return 0
    elif voltage_kv >= 33:
        return 50
    else:
        return 100
```

### Age Normalization
```python
def normalize_age(age_years):
    if age_years <= 10:
        return 0
    elif age_years <= 20:
        return 25
    elif age_years <= 30:
        return 50
    elif age_years <= 40:
        return 75
    else:
        return 100
```

---

## Alternative Metrics Considered (Not Included)

### Transformer Proximity
**Reasoning for exclusion**: While transformer distance matters, it's highly correlated with power line distance and grid density. Including it would over-weight infrastructure proximity without adding new information.

**Potential future addition**: Could be used as a tiebreaker for cabins with similar scores.

### Line Type (Overhead vs Underground/Sea Cable)
**Reasoning for exclusion**: Underground cables indicate BETTER infrastructure (more reliable, expensive investment). This is already captured by grid density and KILE costs.

### Connection Cost Proxy
**Reasoning for exclusion**: Distance to line already captures this. Additional complexity without significant new insight.

---

## Validation Criteria

### Internal Consistency Checks
1. **Score distribution**: Expect normal or right-skewed distribution (most cabins have moderate scores)
2. **Geographic clustering**: Weak scores should cluster in remote mountain areas
3. **KILE correlation**: High KILE costs should correlate with high scores (r > 0.5)
4. **Distance dominance**: Distance metric should be strongest predictor of final score

### Ground Truth Validation
1. **Manual inspection**: Sample 20 high-scoring cabins - verify they're in remote areas with weak grids
2. **Manual inspection**: Sample 20 low-scoring cabins - verify they're near strong grid infrastructure
3. **Company comparison**: Compare scores for cabins served by known weak vs strong grid companies

### Statistical Validation
```sql
-- Score distribution
SELECT
    CASE
        WHEN weak_grid_score >= 90 THEN 'Excellent (90-100)'
        WHEN weak_grid_score >= 70 THEN 'Good (70-89)'
        WHEN weak_grid_score >= 50 THEN 'Moderate (50-69)'
        ELSE 'Poor (0-49)'
    END as category,
    COUNT(*) as cabin_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM cabins
WHERE weak_grid_score IS NOT NULL
GROUP BY 1
ORDER BY MIN(weak_grid_score) DESC;

-- Correlation matrix
SELECT
    CORR(distance_to_line_m, weak_grid_score) as dist_correlation,
    CORR(grid_density_score, weak_grid_score) as density_correlation,
    CORR(grid_age_years, weak_grid_score) as age_correlation
FROM cabins
WHERE weak_grid_score IS NOT NULL;
```

---

## Comparison: Old vs New Approach

| Aspect | Old Approach (Service Areas) | New Approach (Grid Infrastructure) |
|--------|------------------------------|-----------------------------------|
| **Primary Data** | Service area polygons | Power line geometries |
| **Coverage** | 73% initial, 98% after fallback | 100% (all cabins analyzable) |
| **Accuracy** | Approximate (polygon containment) | Precise (actual distances) |
| **Grid Quality Info** | KILE costs only | Distance, density, age, voltage, KILE |
| **Company Assignment** | Geographic area (imprecise) | Line ownership (precise) |
| **Weak Grid Detection** | Impossible (no infrastructure data) | Direct measurement |
| **Actionability** | Low (no infrastructure context) | High (specific grid weaknesses) |

### Key Improvements
1. **Ground truth data**: Actual power line locations vs approximate service areas
2. **Multiple dimensions**: 5 metrics vs 1 (KILE only)
3. **Precision**: Meter-level distances vs polygon containment
4. **Complete coverage**: No gaps from missing service area data
5. **Actionable insights**: Specific grid weaknesses identified per cabin

---

## Implementation Notes

### Performance Considerations
- Use spatial indexes on all geometry columns (GIST indexes)
- Batch process cabins in groups of 1000 (learned from 11_assign_by_batch.sh)
- Pre-compute grid company KILE lookups to avoid repeated joins
- Cache nearest-neighbor queries using temporary tables

### Data Quality Assumptions
1. NVE power line data is current and complete for Agder region
2. Power line `year` field is reliable for age calculations
3. KILE costs are up-to-date (2024 regulatory data)
4. Voltage levels are correctly tagged in spenning_kv field

### Future Enhancements
1. **Seasonal adjustment**: Weight remote cabins higher in winter (outage risk)
2. **Elevation factor**: Higher elevation = more exposure to weather = weaker grid
3. **Road access correlation**: Poor road access often correlates with weak grid
4. **Historical outage data**: If available, directly incorporate outage frequency
5. **Machine learning**: Train model on known weak grid cases to refine weights

---

## References

- NVE (Norges Vassdrags- og Energidirektorat) grid infrastructure data
- NVE KILE regulatory data (2024)
- Kartverket N50 cabin location data
- PostgreSQL/PostGIS spatial analysis capabilities

---

**Document Version**: 1.0
**Last Updated**: 2025-11-22
**Author**: System Architect (Claude Code)
