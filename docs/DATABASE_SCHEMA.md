# Database Schema - Svakenett v4

**Database**: svakenett (PostgreSQL 16 + PostGIS 3.4)
**Version**: 4.0 (Progressive Filtering Approach)
**Last Updated**: 2025-11-24

---

## Overview

The Svakenett v4 database uses PostgreSQL with PostGIS for spatial analysis to identify weak grid buildings through progressive filtering rather than traditional scoring.

**Key Tables**:
- **buildings** (130,250 rows) - All building types nationwide
- **power_lines_new** (9,316 rows) - 11-24 kV distribution lines
- **transformers_new** (106 rows) - Transformer stations
- **weak_grid_candidates_v4** (21 rows) - Final filtered candidates

---

## Core Tables

### buildings
Primary table containing all analyzed buildings (cabins, residential, commercial).

```sql
CREATE TABLE buildings (
    id SERIAL PRIMARY KEY,
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- Building classification
    bygningstype INTEGER,                    -- SSB building type code
    building_type_name VARCHAR(100),         -- Human-readable type
    building_source VARCHAR(50),             -- Classification: cabin/residential/commercial

    -- Location
    postal_code VARCHAR(4),
    kommunenavn VARCHAR(100),

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_buildings_geom ON buildings USING GIST(geometry);
CREATE INDEX idx_buildings_postal ON buildings(postal_code);
CREATE INDEX idx_buildings_type ON buildings(bygningstype);
CREATE INDEX idx_buildings_source ON buildings(building_source);
```

**Row count**: 130,250 buildings
**Building types**:
- Cabins (fritidsbygg): bygningstype 161
- Residential (bolig): bygningstype 111-199 (excluding 161)
- Commercial: All other types

---

### power_lines_new
NVE power line data (11-24 kV distribution lines only).

```sql
CREATE TABLE power_lines_new (
    id SERIAL PRIMARY KEY,
    geometry GEOMETRY(LineString, 4326) NOT NULL,

    -- Line attributes
    spenning_kv INTEGER,                     -- Voltage level (11-24 kV)
    driftsattaar INTEGER,                    -- Year built
    eierorgnr VARCHAR(20),                   -- Owner organization number

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_power_lines_new_geom ON power_lines_new USING GIST(geometry);
CREATE INDEX idx_power_lines_new_voltage ON power_lines_new(spenning_kv);
```

**Row count**: 9,316 power lines
**Voltage range**: 11-24 kV (distribution grid only)
**Geometry type**: Complete LineString geometries (no power poles needed)

---

### transformers_new
Transformer station locations.

```sql
CREATE TABLE transformers_new (
    id SERIAL PRIMARY KEY,
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_transformers_new_geom ON transformers_new USING GIST(geometry);
```

**Row count**: 106 transformer stations
**Geographic coverage**: Nationwide

---

### weak_grid_candidates_v4
Final output table from v4 progressive filtering analysis.

```sql
CREATE TABLE weak_grid_candidates_v4 (
    id INTEGER PRIMARY KEY,

    -- Building info
    bygningstype INTEGER,
    building_type_name VARCHAR(100),
    building_source VARCHAR(50),
    postal_code VARCHAR(4),
    kommunenavn VARCHAR(100),

    -- Infrastructure metrics
    transformer_distance_m REAL,            -- Distance to nearest transformer
    nearest_voltage_kv INTEGER,             -- Nearest power line voltage
    nearest_year_built INTEGER,             -- Nearest power line age
    line_distance_m REAL,                   -- Distance to nearest line
    line_count_1km INTEGER,                 -- Grid density (lines within 1km)
    grid_length_km REAL,                    -- Total line length within 1km

    -- Load concentration metrics
    buildings_within_1km INTEGER,           -- Total buildings nearby
    residential_within_1km INTEGER,         -- Residential buildings nearby
    cabins_within_1km INTEGER,              -- Cabins nearby

    -- Risk classification
    weak_grid_tier VARCHAR(100),            -- Tier 1 Extreme / Tier 2 Severe
    load_severity VARCHAR(100),             -- High/Medium/Low/Isolated
    composite_risk_score REAL,              -- (transformer_dist_km) × (buildings+1)

    -- Geometry
    geometry GEOMETRY(Point, 4326)
);

CREATE INDEX idx_weak_grid_v4_geom ON weak_grid_candidates_v4 USING GIST(geometry);
CREATE INDEX idx_weak_grid_v4_risk ON weak_grid_candidates_v4(composite_risk_score DESC);
CREATE INDEX idx_weak_grid_v4_tier ON weak_grid_candidates_v4(weak_grid_tier);
```

**Row count**: 21 weak grid candidates
**Filtering criteria**:
- Transformer distance >30km
- Distribution line proximity <1km
- Grid density ≤1 line within 1km
- Building density ≥3 buildings within 1km

**Tier definitions**:
- **Tier 1 Extreme**: >50km from transformer
- **Tier 2 Severe**: 30-50km from transformer

**Load severity**:
- **High**: ≥20 buildings within 1km
- **Medium**: 10-19 buildings within 1km
- **Low**: 5-9 buildings within 1km
- **Isolated**: <5 buildings within 1km

---

## Materialized Views

### distribution_lines_11_24kv
Filtered view of power lines for v4 analysis (created during progressive filtering).

```sql
CREATE MATERIALIZED VIEW distribution_lines_11_24kv AS
SELECT
    id,
    geometry,
    spenning_kv as voltage_kv,
    driftsattaar::integer as year_built,
    eierorgnr::text as owner_orgnr
FROM power_lines_new
WHERE spenning_kv BETWEEN 11 AND 24;

CREATE INDEX idx_distribution_lines_geom
    ON distribution_lines_11_24kv USING GIST(geometry);
```

**Row count**: 9,316 power lines
**Purpose**: Pre-filtered dataset for progressive filtering queries
**Performance**: Eliminates need to filter on every query

---

## Legacy Tables (Not Used in v4)

The following tables exist but are **not used** in v4 progressive filtering:

### power_poles
**Status**: ❌ Not used in v4
**Reason**: Improved data quality - complete LineString geometries make poles redundant

### cabins, residential_buildings
**Status**: ❌ Not used in v4
**Reason**: Superseded by unified `buildings` table with `building_source` classification

### postal_code_scores, grid_companies
**Status**: ❌ Not used in v4
**Reason**: KILE scoring removed, progressive filtering doesn't use company-level data

### power_lines (old)
**Status**: ❌ Not used in v4
**Reason**: Superseded by `power_lines_new` with better data quality

---

## v4 Progressive Filtering Workflow

The v4 analysis uses the following SQL workflow:

### Step 0: Create Materialized View
```sql
CREATE MATERIALIZED VIEW distribution_lines_11_24kv AS
SELECT id, geometry, spenning_kv as voltage_kv,
       driftsattaar::integer as year_built, eierorgnr::text as owner_orgnr
FROM power_lines_new
WHERE spenning_kv BETWEEN 11 AND 24;
```
**Output**: 9,316 power lines

### Step 1: Filter by Transformer Distance >30km
```sql
CREATE TEMP TABLE step1_far_from_transformers AS
SELECT b.*,
    ST_Distance(b.geometry::geography,
        (SELECT geometry FROM transformers_new
         ORDER BY b.geometry <-> geometry LIMIT 1)::geography
    ) as transformer_distance_m
FROM buildings b
WHERE NOT EXISTS (
    SELECT 1 FROM transformers_new t
    WHERE ST_DWithin(b.geometry::geography, t.geometry::geography, 30000)
);
```
**Reduction**: 130,250 → 66 buildings (99.95% eliminated)

### Step 2: Filter by Line Proximity <1km
```sql
CREATE TEMP TABLE step2_near_distribution AS
SELECT s1.*, dl.voltage_kv, dl.year_built,
    ST_Distance(s1.geometry::geography, dl.geometry::geography) as line_distance_m
FROM step1_far_from_transformers s1
CROSS JOIN LATERAL (
    SELECT voltage_kv, year_built, geometry
    FROM distribution_lines_11_24kv
    ORDER BY s1.geometry <-> geometry LIMIT 1
) dl
WHERE ST_Distance(s1.geometry::geography, dl.geometry::geography) < 1000;
```
**Reduction**: 66 → 62 buildings (6% eliminated)

### Step 3: Calculate Grid Density
```sql
CREATE TEMP TABLE step3_with_density AS
SELECT s2.*,
    COUNT(dl.id) as line_count_1km,
    COALESCE(SUM(ST_Length(dl.geometry::geography)) / 1000, 0) as grid_length_km
FROM step2_near_distribution s2
LEFT JOIN distribution_lines_11_24kv dl
    ON ST_DWithin(s2.geometry::geography, dl.geometry::geography, 1000)
GROUP BY s2.id, [other columns];
```
**Output**: 62 buildings with grid density calculated

### Step 4: Filter by Low Density ≤1 Line
```sql
CREATE TEMP TABLE step4_sparse_grid AS
SELECT * FROM step3_with_density
WHERE line_count_1km <= 1;
```
**Reduction**: 62 → 21 buildings (66% eliminated)

### Step 5: Calculate Building Density
```sql
CREATE TEMP TABLE step5_with_load_density AS
SELECT s4.*,
    (SELECT COUNT(*) FROM buildings b
     WHERE ST_DWithin(s4.geometry::geography, b.geometry::geography, 1000)
    ) as buildings_within_1km,
    [residential_within_1km, cabins_within_1km calculations]
FROM step4_sparse_grid s4;
```
**Output**: 21 buildings with load concentration calculated

### Step 6: Final Classification
```sql
CREATE TABLE weak_grid_candidates_v4 AS
SELECT *,
    CASE
        WHEN transformer_distance_m > 50000 THEN 'Tier 1: Extreme (>50km)'
        WHEN transformer_distance_m > 30000 THEN 'Tier 2: Severe (30-50km)'
    END as weak_grid_tier,
    (transformer_distance_m / 1000.0) * (buildings_within_1km + 1) as composite_risk_score
FROM step5_with_load_density
WHERE buildings_within_1km >= 3
ORDER BY transformer_distance_m DESC, buildings_within_1km DESC;
```
**Final output**: 21 weak grid candidates

---

## Performance Characteristics

| Operation | Dataset Size | Runtime | Technique |
|-----------|-------------|---------|-----------|
| Step 0: Materialized view | 9,316 lines | 10-30s | One-time cost |
| Step 1: Transformer filter | 130,250 → 66 | 1.4s | ST_DWithin + NOT EXISTS |
| Step 2: Line proximity | 66 → 62 | 0.04s | KNN operator (<->) |
| Step 3: Grid density | 62 buildings | 3.7s | ST_DWithin on small set |
| Step 4: Density filter | 62 → 21 | <0.01s | Attribute filter |
| Step 5: Building density | 21 buildings | 8.8s | ST_DWithin on tiny set |
| Step 6: Classification | 21 buildings | <0.01s | CASE expression |
| **Total** | **130,250 → 21** | **14s** | **Progressive filtering** |

**Key optimizations**:
1. **Filter selectivity first** - 99.95% elimination before calculations
2. **KNN operator** - O(log n) nearest neighbor queries
3. **Materialized views** - Reusable filtered datasets
4. **Progressive reduction** - Each step reduces dataset for next step

---

## Spatial Indexes

All geometry columns have GIST spatial indexes for efficient queries:

```sql
-- Buildings
CREATE INDEX idx_buildings_geom ON buildings USING GIST(geometry);

-- Power lines
CREATE INDEX idx_power_lines_new_geom ON power_lines_new USING GIST(geometry);
CREATE INDEX idx_distribution_lines_geom ON distribution_lines_11_24kv USING GIST(geometry);

-- Transformers
CREATE INDEX idx_transformers_new_geom ON transformers_new USING GIST(geometry);

-- Results
CREATE INDEX idx_weak_grid_v4_geom ON weak_grid_candidates_v4 USING GIST(geometry);
```

**Index type**: GIST (Generalized Search Tree)
**Purpose**: Enables O(log n) spatial queries (ST_DWithin, KNN operator)
**Performance impact**: Critical for 200x speedup

---

## Coordinate System

**SRID**: 4326 (WGS 84)
**Projection**: Geographic (lat/lon)
**Distance calculations**: Use `::geography` cast for accurate meter-based distances

Example:
```sql
ST_Distance(point1::geography, point2::geography)  -- Returns meters
```

---

## Data Sources

| Table | Source | Rows | Update Frequency |
|-------|--------|------|------------------|
| buildings | NVE + Kartverket | 130,250 | Annual |
| power_lines_new | NVE Distribusjonsnett | 9,316 | Quarterly |
| transformers_new | NVE | 106 | Annual |

---

## Comparison with Old Schema (Phase 1-6)

| Aspect | Old Schema | v4 Schema | Change |
|--------|-----------|-----------|--------|
| **Scoring approach** | KILE-based weighted scores | Progressive filtering | Simplified |
| **Power poles** | Separate table with geometry | Not used | Removed |
| **Building tables** | 3 tables (cabins, residential, buildings) | 1 unified table | Consolidated |
| **Grid companies** | Company-level KILE data | Not used | Removed |
| **Postal code aggregation** | GDPR-compliant scores | Not used | Removed |
| **Output** | Score 0-100 for all buildings | 21 high-confidence candidates | Focused |

---

## Future Enhancements

Potential additions for future versions:

1. **Physics-based risk scoring**
   - Non-linear distance scaling
   - Building type load factors (cabins=0.3, residential=1.0, commercial=2.0)

2. **Economic viability layer**
   - Solar irradiance data (NASA POWER API)
   - ROI calculations (solar+battery vs grid reinforcement)
   - Electricity price integration

3. **Grid operator integration**
   - Actual load data
   - Known weak grid area designations
   - Capacity constraints

4. **Real-time monitoring**
   - Automated alerting for new candidates
   - Incremental updates
   - Dashboard for decision support

---

**Document Version**: 4.0
**Last Updated**: 2025-11-24
**Status**: Production (Nationwide Analysis)
