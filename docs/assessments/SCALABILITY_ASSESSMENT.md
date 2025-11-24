# Scalability Assessment: Regional MVP to National System

**Document Version:** 1.0
**Date:** November 21, 2025
**Transition Scope:** Agder MVP (15k properties) → National System (90k properties)
**Author:** System Architecture Analysis

---

## EXECUTIVE SUMMARY

**Primary Conclusion:** The MVP architecture is fundamentally sound for national scaling, but requires strategic upgrades at 3 critical thresholds:

1. **40,000+ properties:** Migrate SQLite → PostgreSQL+PostGIS
2. **50,000+ properties:** Implement parallel processing and batch optimization
3. **National rollout:** Automate data acquisition and implement CRM integration

**Feasibility Rating:** ✅ **HIGHLY FEASIBLE** - MVP designed with scalability principles

**Critical Bottlenecks Identified:**
- Database performance (SQLite limit: ~50k geospatial records)
- Manual data acquisition (1 county → 11 counties = 11x effort)
- Memory constraints (GeoPandas loading all geometries)
- Grid company data aggregation complexity (1 company → 100+ companies)

**Recommended Approach:**
- Build MVP as planned with SQLite (optimize for speed-to-market)
- Include PostgreSQL migration scripts in MVP codebase
- Design data processing pipeline with national scale in mind
- Implement modular architecture allowing incremental scaling

**Budget Impact:**
- MVP: 200k NOK (2-4 weeks)
- National scaling infrastructure: +150k NOK
- Total Phase 2: 500k NOK (includes ML model + CRM integration)

---

## 1. DATA VOLUME SCALING (15k → 90k properties)

### Current State (MVP)
- **Dataset:** ~15,000 cabin records (Agder region)
- **Database:** SQLite + SpatiaLite (file-based)
- **Processing:** pandas + GeoPandas in-memory operations
- **Query pattern:** Batch geospatial distance calculations
- **Estimated processing time:** 5-8 minutes for full analysis

### Target State (Phase 2)
- **Dataset:** ~90,000 properties (cabins + farms + rural homes)
- **6x data volume increase**
- **Expected processing time (naive scaling):** 30-48 minutes
- **Target processing time:** <15 minutes with optimization

### Performance Analysis

#### SQLite + SpatiaLite Limitations

**Practical Limits:**
- ✅ **0-25k records:** Excellent performance (<2 min processing)
- ⚠️ **25-50k records:** Acceptable performance (2-10 min processing)
- ❌ **50k+ records:** Degraded performance (>15 min, risk of memory issues)

**Critical Operations:**
```sql
-- Geospatial distance query (most expensive operation)
SELECT building_id,
       MIN(ST_Distance(building.geometry, power_line.geometry)) as dist_m
FROM buildings
CROSS JOIN power_lines
GROUP BY building_id
```

**Performance Estimates:**
- 15k buildings × 5k power line segments = 75M distance calculations
- 90k buildings × 30k power line segments = 2.7B distance calculations (**36x increase**)
- SQLite with SpatiaLite: **Cannot efficiently index this at national scale**

**Bottleneck Threshold:** ~40,000 properties (before query time becomes unacceptable)

#### PostgreSQL + PostGIS Solution

**Why PostgreSQL at national scale:**
- **Spatial indexing:** GIST indexes reduce query complexity from O(n²) to O(n log n)
- **Parallel query execution:** Multi-core utilization (SQLite is single-threaded)
- **Query optimizer:** Better join strategies for large datasets
- **Partial indexes:** Index only high-priority property types
- **Connection pooling:** Support concurrent read operations

**Performance Improvement Estimate:**
- 90k property analysis with PostgreSQL+PostGIS: **5-10 minutes** (vs. 45+ min with SQLite)
- Memory usage: **Stable** (streaming queries vs. full in-memory load)

### Memory Usage Analysis

**GeoPandas Memory Footprint:**

```python
# MVP (15k properties)
buildings_gdf = gpd.GeoDataFrame(...)  # ~50 MB in RAM
power_lines_gdf = gpd.read_file(...)   # ~20 MB
Total: ~70 MB (easily fits in 4GB RAM)

# National (90k properties)
buildings_gdf = gpd.GeoDataFrame(...)  # ~300 MB
power_lines_gdf = gpd.read_file(...)   # ~120 MB (all Norway)
Total: ~420 MB (still manageable, but risky for operations)
```

**Risk:** GeoPandas spatial joins create temporary arrays that can spike to 3-5x base memory usage.

**Mitigation Strategies:**
1. **Chunked processing:** Process properties in batches of 10k
2. **Streaming from database:** Load geometries on-demand via SQL queries
3. **Geometry simplification:** Reduce coordinate precision for distance calculations
4. **Spatial indexing:** Pre-filter candidates before exact distance calculation

### Migration Strategy

**Recommended Timeline:**

```
Phase 1 (MVP): 0-15k properties
├─ Database: SQLite + SpatiaLite
├─ Processing: pandas + GeoPandas (full in-memory)
├─ Rationale: Fastest development, sufficient performance
└─ Cost: 0 NOK (included in Python stack)

Phase 1.5 (Regional expansion): 15-40k properties
├─ Database: Still SQLite (with optimization)
├─ Processing: Chunked GeoPandas (10k property batches)
├─ Optimization: Add spatial indexes, simplify geometries
└─ Cost: 0 NOK (optimization work)

Phase 2 (National): 40k+ properties
├─ Database: PostgreSQL 15+ with PostGIS 3.4
├─ Processing: Streaming SQL queries + targeted GeoPandas
├─ Infrastructure: Cloud database instance (GCP Cloud SQL)
└─ Cost: +40k NOK/year (database hosting)
```

**Migration Complexity:** ⚠️ **MODERATE**

**Migration Script Structure:**
```python
# migration/sqlite_to_postgres.py

def migrate_spatial_data():
    """
    One-time migration from SQLite to PostgreSQL
    """
    # 1. Export SQLite tables to CSV
    sqlite_conn = sqlite3.connect('weak_grid_mvp.db')
    tables = ['buildings', 'power_lines', 'grid_companies', 'kile_stats']

    for table in tables:
        df = pd.read_sql(f"SELECT * FROM {table}", sqlite_conn)
        df.to_csv(f"export_{table}.csv", index=False)

    # 2. Import to PostgreSQL with PostGIS
    pg_conn = psycopg2.connect(DATABASE_URL)
    for table in tables:
        # Create PostGIS geometry columns
        # Import CSV data
        # Create spatial indexes

    # 3. Validate record counts
    # 4. Run test queries
    # 5. Benchmark performance
```

**Testing Requirements:**
- Validate 100% data integrity (no lost records)
- Benchmark query performance (must be <2x MVP speed at 3x data volume)
- Test concurrent read operations (simulate 5 users)

### Recommendations

**✅ MVP Decision: Use SQLite**
- **Rationale:** 15k properties well within performance envelope
- **Benefit:** Zero infrastructure costs, simpler development
- **Risk mitigation:** Include PostgreSQL migration scripts in MVP repository

**⚠️ Scale-Up Decision Point: 40k properties**
- **Trigger:** When expanding beyond 3 counties OR processing time >10 minutes
- **Action:** Execute migration to PostgreSQL+PostGIS
- **Timeline:** 3-5 days for migration + testing

**🎯 Performance Target:**
- MVP (15k): <5 minutes processing ✅
- Regional (40k): <8 minutes processing (optimized SQLite) ✅
- National (90k): <12 minutes processing (PostgreSQL) ✅

---

## 2. GEOGRAPHIC COVERAGE SCALING (1 County → All Norway)

### Current State (MVP)
- **Region:** Agder fylke (25 municipalities)
- **Grid companies:** 1-2 primary (Agder Energi Nett, Linea AS)
- **Data sources:**
  - N50 building data for Agder (manual download from Geonorge)
  - KILE statistics for Agder grid companies (single Excel sheet)
  - Power line data (manually digitized from Agder Energi web maps)

### Target State (Phase 2)
- **Region:** All Norway (356 municipalities, 11 counties)
- **Grid companies:** 100+ distribution system operators (DSOs)
- **Data sources:**
  - N50 building data for entire country (Kartverket bulk API required)
  - KILE statistics for all grid companies (NVE national dataset)
  - Power line data from NVE Atlas (national WMS/WFS service)

### Data Acquisition Complexity

#### N50 Building Data (Kartverket)

**MVP Approach:**
```
1. Visit Geonorge kartkataloget (https://kartkatalog.geonorge.no/)
2. Search "N50 Kartdata - Agder"
3. Download GML/GeoJSON file (1-2 GB)
4. Manual processing with GDAL/ogr2ogr
5. Filter to building types: fritidsbolig, våningshus, driftsbygning

Time: 1 day (manual download + processing)
Cost: 0 NOK (free public data)
```

**National Approach (Option A: Manual per county):**
```
1. Repeat above process for 11 counties
2. Download 11 separate files (total 12-15 GB)
3. Merge into national dataset
4. Resolve coordinate system inconsistencies

Time: 3-4 days (repetitive manual work)
Cost: 0 NOK
Risk: Human error in download/merge process
```

**National Approach (Option B: Kartverket API - RECOMMENDED):**
```
1. Apply for Matrikkelen API access agreement (Kartverket)
   - Application form: https://www.kartverket.no/api-og-data/bestill
   - Processing time: 2-4 weeks
   - Cost: 10,000 NOK one-time agreement fee

2. Use WFS API to fetch building data programmatically
   - Automated county-by-county download
   - Consistent format (GeoJSON)
   - Automatic coordinate system handling

3. Schedule monthly updates via API (keep data current)

Time: 1 week (initial setup), then automated
Cost: 10,000 NOK agreement + API usage (minimal)
Benefit: Fully automated, always current data
```

**Recommendation:** Invest in Kartverket API for national scale (mandatory for Phase 2).

#### KILE Statistics (NVE)

**MVP Approach:**
```
1. Download NVE KILE Excel file: "KILE-2023-nettselskap.xlsx"
2. Filter to Agder Energi Nett AS + Linea AS
3. Extract SAIDI, SAIFI, KILE compensation values

Time: 1 hour
Complexity: LOW (single Excel file with all grid companies)
```

**National Approach:**
```
1. Download same NVE KILE Excel file (contains all 100+ companies)
2. Map property locations to correct grid company (via spatial join)
3. Handle companies with missing data (new companies, merged entities)
4. Aggregate regional variations (e.g., Finnmark vs. Oslo)

Time: 1 day (mapping logic + data cleaning)
Complexity: MODERATE (grid company boundary mapping)
```

**Scaling Challenge:** **Grid company coverage areas are not perfectly defined**

- NVE provides company names but NOT geographic boundaries
- Must infer boundaries from:
  - Municipality assignments (approximate)
  - Elhub data (requires API access)
  - Manual research of company websites

**Mitigation Strategy:**
```python
# Build grid company lookup table
grid_company_map = {
    "0301": "Elvia AS",              # Oslo municipality code
    "4626": "Agder Energi Nett AS",  # Kristiansand
    "5401": "Haugaland Kraft AS",    # Haugesund
    # ... 356 municipality mappings
}

# Fallback: Use nearest neighbor for ambiguous cases
def assign_grid_company(municipality_code, latitude, longitude):
    # Primary: Municipality lookup
    if municipality_code in grid_company_map:
        return grid_company_map[municipality_code]

    # Fallback: Spatial query to nearest grid company service area
    return find_nearest_grid_company_spatial(latitude, longitude)
```

**Complexity Multiplier:** 2-3x effort (from simple lookup to spatial mapping)

#### Power Line Data (NVE Atlas)

**MVP Approach:**
```
1. Visit Agder Energi Nett's public web map
2. Manually trace major power lines (high voltage transmission)
3. Digitize as GeoJSON (using QGIS or similar)
4. Focus on lines >22 kV (cabin connection candidates)

Time: 3-5 days (manual digitization)
Coverage: ~80% of actual lines (approximation acceptable)
Cost: Labor only
```

**National Approach (Automated via NVE Atlas API):**
```
1. Access NVE Atlas WMS/WFS service
   URL: https://gis3.nve.no/map/services/Kraftledninger/MapServer/WMSServer

2. Query power line data programmatically:
   - Filter: Voltage >22 kV
   - Extent: National bounding box
   - Format: GeoJSON

3. Download and cache locally (NVE Atlas can be slow)

Time: 1-2 days (API integration + data validation)
Coverage: 100% of registered lines (official NVE data)
Cost: 0 NOK (free public WMS service)
```

**Scaling Benefit:** **Automated approach is FASTER than manual** (despite 6x geographic area)

**Data Quality Considerations:**
- NVE Atlas data quality varies by region (rural areas less detailed)
- Some private cabin area power lines not registered in NVE system
- Need fallback heuristic: "If no power line within 5 km, assume no grid connection"

### Regional Scoring Model Adaptations

**MVP Scoring Weights (Agder-optimized):**
```
Geographic factors:  40 points
├─ Distance to power line: 15p
├─ Population density: 10p
├─ Neighbors within 500m: 10p
└─ Distance to public road: 5p

Grid company factors: 30 points
├─ KILE SAIDI (outage duration): 15p
├─ KILE SAIFI (outage frequency): 10p
└─ Network loss percentage: 5p

Property factors: 30 points
├─ Building type (cabin=20p, farm=10p): 20p
├─ Building age (<1950=5p): 5p
└─ Floor area (>150m²=5p): 5p
```

**Question:** Do these weights work for all Norwegian regions?

**Regional Variations to Consider:**

| Region | Grid Quality | Terrain | Climate | Scoring Adjustment |
|--------|--------------|---------|---------|-------------------|
| **Agder (South)** | Good | Moderate hills | Mild | Baseline (100%) |
| **Finnmark (North)** | Weaker | Extreme terrain | Arctic | KILE weight +10p (more outages) |
| **Oslo/Viken** | Excellent | Flat | Mild | Geographic weight -5p (dense infra) |
| **Vestland (West)** | Good | Fjords/mountains | Wet | Terrain complexity +5p |
| **Trøndelag** | Moderate | Rolling | Cold winters | Balanced (100%) |

**Recommendation:** **SEGMENTED SCORING MODELS**

```python
# Define regional scoring profiles
SCORING_PROFILES = {
    "southern_norway": {  # Agder, Rogaland, Vestfold
        "geographic_weight": 0.40,
        "grid_weight": 0.30,
        "property_weight": 0.30,
        "kile_multiplier": 1.0,
    },
    "northern_norway": {  # Finnmark, Troms, Nordland
        "geographic_weight": 0.35,
        "grid_weight": 0.40,  # Higher - more outages
        "property_weight": 0.25,
        "kile_multiplier": 1.5,  # Adjust for harsh climate
    },
    "urban_norway": {  # Oslo, Bergen, Trondheim suburbs
        "geographic_weight": 0.30,
        "grid_weight": 0.25,
        "property_weight": 0.45,  # Property type matters more
        "kile_multiplier": 0.8,  # Better grids
    },
}

def calculate_score(property_data, region_profile):
    base_score = calculate_base_score(property_data)

    # Apply regional weights
    weighted_score = (
        property_data.geo_score * region_profile["geographic_weight"] +
        property_data.grid_score * region_profile["grid_weight"] +
        property_data.property_score * region_profile["property_weight"]
    )

    return weighted_score
```

**Validation Strategy:**
- Test scoring model against actual Norsk Solkraft customer data from different regions
- If recall drops below 60% in a region, create region-specific calibration
- Collect feedback from sales team on lead quality by region

### Data Acquisition Effort Multiplier

**Summary Table:**

| Data Source | MVP Effort | National Effort | Multiplier | Mitigation |
|-------------|-----------|-----------------|-----------|-----------|
| **N50 Building Data** | 1 day manual | 3-4 days manual OR 1 week automated | 3-4x → **1x with API** | Use Kartverket API (invest 10k NOK) |
| **KILE Statistics** | 1 hour | 1 day | 8x → **4x with mapping table** | Pre-build grid company lookup |
| **Power Line Data** | 3-5 days manual | 1-2 days automated | **0.3x** (faster!) | Use NVE Atlas WMS/WFS |
| **Regional Calibration** | 0 days | 2-3 days | N/A | Build regional scoring profiles |
| **TOTAL** | 5-7 days | 7-10 days with automation | **1.5x** | Automation investment pays off |

**Key Insight:** With proper API access, national data acquisition is only **1.5x** the effort of MVP (not 11x as naively expected).

**Critical Path Item:** **Kartverket API agreement (2-4 week lead time)** - must be initiated ASAP in Phase 2.

---

## 3. PROPERTY TYPE DIVERSITY (Cabins → Cabins + Farms + Rural Homes)

### Current State (MVP)
- **Property Type:** Cabins only (fritidsbolig)
- **Scoring optimization:** Tuned for "weekend use, low baseline consumption, wants occasional high power"
- **Data source:** SSB cabin statistics (clean category definition)
- **Market understanding:** Clear use case (cabin + varmepumpe + elbillader)

### Target State (Phase 2)
- **Property Types:**
  - Cabins (fritidsbolig): ~60% of target market
  - Farms (gårdsbruk, driftsbygning): ~25% of target market
  - Rural homes (våningshus in low-density areas): ~15% of target market

### Property Type Classification

**N50 Building Type Taxonomy (Kartverket):**

```
Relevant building types in N50:
├─ 161 "Fritidsbolig" → CABIN (direct match)
├─ 111 "Våningshus" → RURAL HOME (needs density filter)
├─ 121 "Driftsbygning, gårdsbruk" → FARM BUILDING (direct match)
├─ 171 "Anneks" → SECONDARY CABIN (treat as cabin)
└─ 239 "Lagerbygg" → EXCLUDE (not residential)
```

**Classification Challenge:** **"Våningshus" includes both:**
- Urban/suburban homes (NOT target market)
- Rural homes with weak grid (TARGET market)

**Solution: Density-Based Filter**

```python
def classify_property_type(building_row):
    """
    Classify property into cabin, farm, or rural home
    """
    building_type = building_row['building_code']
    population_density = building_row['pop_density_per_km2']
    neighbors_500m = building_row['neighbor_count_500m']

    if building_type == 161:  # Fritidsbolig
        return "cabin"

    elif building_type == 121:  # Driftsbygning
        return "farm"

    elif building_type == 111:  # Våningshus
        # Rural home definition: Low density + few neighbors
        if population_density < 10 and neighbors_500m < 5:
            return "rural_home"
        else:
            return "urban_home"  # EXCLUDE from scoring

    else:
        return "other"  # EXCLUDE
```

**Data Source Adequacy:** ✅ **SUFFICIENT** - N50 building types can reliably distinguish target segments.

### Scoring Model Variations

**Question:** Should cabins, farms, and rural homes use the same scoring model?

**Answer:** **NO** - Different power needs and usage patterns require segmented models.

#### Cabin Scoring Model (Existing MVP)

```python
# Optimized for: Occasional high power (varmepumpe, elbillader)
CABIN_SCORING = {
    "distance_to_power_line": {
        "weight": 15,
        "thresholds": [500, 1000],  # meters
        "scores": [0, 8, 15]
    },
    "kile_saidi": {
        "weight": 15,
        "thresholds": [60, 180],  # minutes/year
        "scores": [0, 8, 15]
    },
    "building_type_bonus": 20,  # Cabin = automatic high priority
}
```

#### Farm Scoring Model (New for Phase 2)

```python
# Optimized for: Continuous high power (verksted, machinery, livestock)
FARM_SCORING = {
    "distance_to_power_line": {
        "weight": 12,  # Less critical (farms usually connected)
        "thresholds": [1000, 2000],  # Longer acceptable distance
        "scores": [0, 6, 12]
    },
    "kile_saidi": {
        "weight": 20,  # MORE critical (livestock risk with outages)
        "thresholds": [30, 120],  # Stricter thresholds
        "scores": [0, 10, 20]
    },
    "building_type_bonus": 10,  # Lower bonus (not all farms need offgrid)
    "operational_need_indicator": 15,  # NEW: Size of farm, livestock presence
}
```

#### Rural Home Scoring Model (New for Phase 2)

```python
# Optimized for: Permanent residence with modern power needs
RURAL_HOME_SCORING = {
    "distance_to_power_line": {
        "weight": 10,  # Least critical (homes usually connected)
        "thresholds": [800, 1500],
        "scores": [0, 5, 10]
    },
    "kile_saidi": {
        "weight": 18,  # Important (permanent residence)
        "thresholds": [45, 150],
        "scores": [0, 9, 18]
    },
    "building_type_bonus": 5,  # Low bonus (many alternatives available)
    "demographic_indicator": 12,  # NEW: Household size, EV ownership likelihood
}
```

### Market Segmentation Strategy

**Recommended Approach:** **3 SEPARATE SCORING PIPELINES**

```python
# Pseudo-code for segmented scoring
def score_properties(national_buildings_gdf):
    """
    Apply property-type-specific scoring models
    """
    # Split into segments
    cabins = national_buildings_gdf[
        national_buildings_gdf['property_type'] == 'cabin'
    ].copy()

    farms = national_buildings_gdf[
        national_buildings_gdf['property_type'] == 'farm'
    ].copy()

    rural_homes = national_buildings_gdf[
        national_buildings_gdf['property_type'] == 'rural_home'
    ].copy()

    # Score each segment with dedicated model
    cabins['weak_grid_score'] = cabins.apply(cabin_scoring_model, axis=1)
    farms['weak_grid_score'] = farms.apply(farm_scoring_model, axis=1)
    rural_homes['weak_grid_score'] = rural_homes.apply(rural_home_scoring_model, axis=1)

    # Combine and rank
    all_scored = pd.concat([cabins, farms, rural_homes])

    # Generate segment-specific lead lists
    top_cabin_leads = cabins.nlargest(500, 'weak_grid_score')
    top_farm_leads = farms.nlargest(200, 'weak_grid_score')
    top_home_leads = rural_homes.nlargest(100, 'weak_grid_score')

    return {
        "cabins": top_cabin_leads,
        "farms": top_farm_leads,
        "rural_homes": top_home_leads,
    }
```

**Benefit:** Sales team can target different segments with tailored messaging.

**Marketing Examples:**
- **Cabins:** "Få varmepumpe og elbillader på hytta - uten kostbar nettoppgradering"
- **Farms:** "Elektrifiser gården med backup-strøm som sikrer dyrevelferd"
- **Rural Homes:** "Moderne bokomfort uten nettselskapets kø"

### Additional Data Sources Needed

**For Farm Segment:**
- **Agricultural Register (Landbruksregisteret):** Livestock type, farm size
- **Data Source:** Mattilsynet / Landbruksdirektoratet
- **Accessibility:** Requires data sharing agreement (GDPR considerations)
- **Value:** Identify high-priority farms (dairy = high backup power need)

**For Rural Home Segment:**
- **Vehicle Registration Data:** Identify EV owners in rural areas
- **Data Source:** Statens vegvesen (SVV)
- **Accessibility:** NOT publicly available (privacy protected)
- **Workaround:** Use demographic proxies (income, municipality EV adoption rate)

**Phase 2 Data Requirements:**
- ✅ **Available:** N50 building types (sufficient for basic segmentation)
- ⚠️ **Requires agreement:** Agricultural register (optional, enhances farm scoring)
- ❌ **Not available:** Individual EV ownership (use proxy indicators)

### Complexity Assessment

**Property Type Diversity Impact:**

| Aspect | MVP (Cabins Only) | Phase 2 (3 Segments) | Complexity Increase |
|--------|------------------|---------------------|---------------------|
| **Data Classification** | Simple (1 building type) | Moderate (3 types + density filter) | 2x effort |
| **Scoring Models** | 1 model, well-tested | 3 models, need validation | 3x effort (initial), 1.5x ongoing |
| **Lead Lists** | Single CSV output | 3 separate lists + combined ranking | 1.5x effort |
| **Sales Process** | Unified pitch | Segment-specific messaging | 2x training effort |
| **Validation** | Compare to existing cabin customers | Need farm + rural home customer data | 2x validation effort |

**Overall Complexity Multiplier:** **1.8x** (manageable with modular design)

### Recommendations

**✅ Implement Segmented Scoring from Day 1 of Phase 2**
- Rationale: Easier to build correctly than refactor later
- Design MVP with extensible scoring framework (prepare for Phase 2)

**📊 Prioritize Cabin Leads Initially, Expand Gradually**
- Phase 2.0: Launch cabin scoring nationally (proven model)
- Phase 2.1: Add farm segment (3 months later, after validation)
- Phase 2.2: Add rural home segment (6 months later)

**🧪 Validation Requirements:**
- Test farm scoring model against ≥20 actual farm customers
- Test rural home model against ≥15 actual rural home customers
- Target: ≥60% recall per segment (lower than cabin's 70% acceptable)

---

## 4. FEATURE COMPLEXITY SCALING (Rule-Based → ML-Enhanced)

### Current State (MVP)
- **Model Type:** Rule-based scoring (deterministic)
- **Algorithm:** Weighted formula with IF-THEN logic
- **Transparency:** Fully explainable (sales team can see exact score breakdown)
- **Adjustability:** Weights can be tuned manually based on sales feedback
- **Training Data Required:** NONE (expert knowledge encoded in rules)

### Target State (Phase 2 Plan)
- **Model Type:** Machine Learning (Random Forest Classifier)
- **Algorithm:** Ensemble decision trees learning from historical conversions
- **Transparency:** Partial (feature importance available, but not exact decision path)
- **Adjustability:** Requires retraining with new data
- **Training Data Required:** Historical customer conversion data

### ML Prerequisites

#### Training Data Requirements

**Minimum Viable Training Dataset:**

```python
# Required data structure
ml_training_data = pd.DataFrame({
    # Features (same as rule-based scoring inputs)
    "dist_to_power_line_m": [...],
    "population_density": [...],
    "neighbors_500m": [...],
    "kile_saidi": [...],
    "kile_saifi": [...],
    "building_type": [...],
    "building_age": [...],
    "floor_area_m2": [...],

    # Target variable (labeled by sales team)
    "became_customer": [1, 0, 1, 0, ...],  # Binary: 1=converted, 0=did not
})
```

**Question:** After MVP, how many conversions needed to train reliable ML model?

**Answer:** Depends on model complexity and class balance.

**Statistical Requirements:**

| Metric | Minimum | Recommended | Ideal |
|--------|---------|-------------|-------|
| **Total labeled examples** | 100 | 300 | 1,000+ |
| **Positive class (customers)** | 30 | 100 | 300+ |
| **Negative class (non-customers)** | 70 | 200 | 700+ |
| **Class balance ratio** | 1:2 | 1:2 to 1:3 | 1:2 to 1:5 |
| **Data collection time (est.)** | 3-6 months | 12-18 months | 24+ months |

**Realistic Timeline:**

```
MVP Launch (Month 0): Deploy rule-based model
├─ Generate 500 high-priority leads
├─ Sales team contacts leads over 3-6 months
├─ Track conversions: ~5-10% conversion rate = 25-50 customers
└─ Label non-customers: All contacted leads that didn't convert

Month 6: First ML Training Attempt
├─ Training set: ~250 labeled examples (50 positive, 200 negative)
├─ Model performance: Likely WORSE than rule-based (insufficient data)
└─ Decision: Continue with rule-based model

Month 12: Second ML Training Attempt
├─ Training set: ~600 labeled examples (120 positive, 480 negative)
├─ Model performance: May MATCH rule-based (still risky to deploy)
└─ Decision: A/B test ML vs. rule-based

Month 18-24: ML Deployment
├─ Training set: ~1,200 labeled examples (240 positive, 960 negative)
├─ Model performance: OUTPERFORMS rule-based (10-15% better precision)
└─ Decision: Deploy ML model to production
```

**Critical Insight:** **ML is a Phase 3 feature, not Phase 2.**

### Trade-offs: Rules vs. ML

#### Rule-Based Scoring (MVP & Phase 2)

**Advantages:**
- ✅ **No training data required** - can deploy immediately
- ✅ **Fully explainable** - sales team knows why lead scored high
- ✅ **Easily adjustable** - change weights based on feedback
- ✅ **Transparent to customers** - can explain scoring in marketing
- ✅ **Consistent** - same inputs always produce same score
- ✅ **Debuggable** - errors are traceable to specific rules

**Disadvantages:**
- ❌ **Expert bias** - relies on assumptions, not data
- ❌ **Limited adaptability** - can't learn from new patterns
- ❌ **Manual tuning** - requires ongoing maintenance
- ❌ **Fixed interactions** - can't discover complex feature relationships

**Best Use Case:** MVP and initial national rollout (until sufficient training data).

#### ML-Based Scoring (Phase 3+)

**Advantages:**
- ✅ **Data-driven** - learns actual patterns from conversions
- ✅ **Automatic optimization** - finds best feature weights
- ✅ **Discovers interactions** - can learn "cabin + high KILE + fjord terrain = convert"
- ✅ **Improves over time** - retraining with more data increases accuracy
- ✅ **Handles non-linear patterns** - better for complex market dynamics

**Disadvantages:**
- ❌ **Requires training data** - needs 300-1,000+ labeled examples
- ❌ **Black box** - harder to explain to sales team ("the algorithm decided")
- ❌ **Overfitting risk** - may learn spurious patterns from small datasets
- ❌ **Maintenance burden** - requires retraining, monitoring, versioning
- ❌ **Explainability challenges** - harder to justify scoring to customers

**Best Use Case:** After 12-24 months of operation with validated conversion data.

### Decision Point: When to Switch from Rules to ML

**Recommended Trigger Conditions:**

```
Switch to ML when ALL of these are true:
├─ ✅ Have ≥300 labeled examples (≥100 positive class)
├─ ✅ Rule-based model has been in production ≥12 months
├─ ✅ ML model outperforms rule-based by ≥10% in A/B test
├─ ✅ Sales team comfortable with reduced explainability
└─ ✅ Have ML ops infrastructure (model versioning, monitoring)
```

**A/B Testing Strategy:**

```python
# Split lead generation between rule-based and ML
def generate_leads(properties_df, month):
    """
    A/B test: 80% rule-based, 20% ML (first 6 months)
    """
    properties_df['assigned_model'] = np.random.choice(
        ['rule_based', 'ml_model'],
        size=len(properties_df),
        p=[0.8, 0.2]  # 80/20 split
    )

    # Score with assigned model
    rule_based_props = properties_df[properties_df['assigned_model'] == 'rule_based']
    ml_props = properties_df[properties_df['assigned_model'] == 'ml_model']

    rule_based_leads = score_rule_based(rule_based_props).nlargest(400, 'score')
    ml_leads = score_ml_model(ml_props).nlargest(100, 'score')

    return pd.concat([rule_based_leads, ml_leads])

# Track conversion rate by model
def evaluate_model_performance():
    """
    After 3 months, compare conversion rates
    """
    rule_conv_rate = conversions_rule / leads_generated_rule
    ml_conv_rate = conversions_ml / leads_generated_ml

    if ml_conv_rate > rule_conv_rate * 1.10:
        print("✅ ML model wins - increase allocation to 50/50")
    else:
        print("⚠️ Rule-based still better - continue current split")
```

### Explainability Considerations

**Sales Team Needs:**
- "Why did this cabin score 87/100?" → Need answer for customer conversations
- "This lead was a waste of time - why did we contact them?" → Need debugging capability
- "Can we adjust scoring to prioritize X region?" → Need tunable parameters

**Rule-Based Explainability (Example):**
```python
# Easy to explain
def explain_score(property_data, score):
    """
    Generate human-readable explanation
    """
    breakdown = {
        "Distance to power line (>1km)": 15,
        "KILE outages (>180 min/year)": 15,
        "Cabin building type": 20,
        "Few neighbors (<5 within 500m)": 10,
        "TOTAL": 87,
    }
    return breakdown

# Sales team sees:
# "This cabin scored 87/100 because:
#  - Very long distance to power grid (15 points)
#  - Frequent power outages in area (15 points)
#  - Prime cabin type (20 points)
#  ..."
```

**ML Explainability (Example with SHAP):**
```python
import shap

# More complex to explain
def explain_ml_prediction(property_data, model):
    """
    Use SHAP values for local explanation
    """
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(property_data)

    # Output: Feature importance values (harder to interpret)
    # dist_to_power_line_m: +0.23
    # kile_saidi: +0.18
    # building_type_cabin: +0.15
    # ...

    # Sales team sees:
    # "The model predicts this is a good lead because distance to
    #  power line has high importance (technical explanation needed)"
```

**Recommendation:** **Keep rule-based scoring available as fallback** even after ML deployment.

### Recommendations

**✅ MVP & Phase 2: Use Rule-Based Scoring**
- Rationale: No training data available, explainability crucial
- Design: Make scoring weights configurable (prepare for tuning)

**📊 Phase 2: Implement Data Collection Infrastructure**
- Track ALL lead outcomes (converted, contacted but declined, not contacted)
- Build labeled dataset for future ML training
- Target: 300+ labeled examples within 12 months

**🧪 Phase 3 (18-24 months): Introduce ML as A/B Test**
- Train Random Forest on historical conversions
- Run 80/20 split (rule-based / ML) for 6 months
- Deploy ML fully only if >10% improvement proven

**🔄 Long-term: Hybrid Approach**
- Use ML for scoring, but provide rule-based explanation overlay
- Allow sales team to override ML predictions when necessary
- Retrain ML model quarterly with new conversion data

**⚠️ Warning: Don't Rush ML Deployment**
- Common mistake: Deploy ML with <100 training examples (will perform WORSE than rules)
- Patience required: Wait for sufficient data collection

---

## 5. INFRASTRUCTURE SCALING (File-Based → Production System)

### Current State (MVP)
- **Execution:** Python script run manually on developer laptop
- **Data storage:** SQLite file (`weak_grid_mvp.db`, ~50 MB)
- **Data refresh:** Manual (analyst downloads new data, runs script)
- **Output:** Static CSV files + HTML maps (stored locally)
- **Distribution:** Email CSV to sales team, share HTML maps via file server
- **CRM integration:** NONE (sales team manually imports leads)

### Target State (Phase 2)
- **Execution:** Scheduled automated pipeline (monthly data updates)
- **Data storage:** Cloud database (PostgreSQL on GCP Cloud SQL)
- **Data refresh:** Automated (API calls to Kartverket, NVE, SSB)
- **Output:** Dynamic web dashboard + API endpoints
- **Distribution:** Sales team accesses web portal, CRM auto-imports via API
- **CRM integration:** REST API to SuperOffice/HubSpot

### Infrastructure Evolution Roadmap

#### Stage 1: MVP (Laptop Script)

```
┌─────────────────────────────────────┐
│   Developer Laptop                  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ Python Script (run manually) │  │
│  │  - data_ingestion.py         │  │
│  │  - scoring_engine.py         │  │
│  │  - visualization.py          │  │
│  └─────────────┬────────────────┘  │
│                │                    │
│  ┌─────────────▼────────────────┐  │
│  │ SQLite Database              │  │
│  │  weak_grid_mvp.db            │  │
│  └─────────────┬────────────────┘  │
│                │                    │
│  ┌─────────────▼────────────────┐  │
│  │ Output Files                 │  │
│  │  - leads.csv                 │  │
│  │  - map.html                  │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Characteristics:**
- ✅ Fast development
- ✅ Zero infrastructure cost
- ❌ Manual execution (error-prone)
- ❌ No version control of results
- ❌ Not accessible to sales team in real-time

**Suitable for:** MVP validation (2-4 weeks)

#### Stage 2: Scheduled Cloud Execution

```
┌─────────────────────────────────────┐
│   Google Cloud Platform             │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ Cloud Run (Scheduled Job)    │  │
│  │  - Runs monthly on 1st       │  │
│  │  - Executes Python pipeline  │  │
│  └─────────────┬────────────────┘  │
│                │                    │
│  ┌─────────────▼────────────────┐  │
│  │ Cloud SQL (PostgreSQL)       │  │
│  │  - PostGIS enabled           │  │
│  │  - Stores all property data  │  │
│  └─────────────┬────────────────┘  │
│                │                    │
│  ┌─────────────▼────────────────┐  │
│  │ Cloud Storage (GCS)          │  │
│  │  - Stores output CSVs        │  │
│  │  - Hosts HTML maps           │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
         │
         │ Download CSV
         ▼
┌─────────────────────────┐
│  Sales Team             │
│  - Downloads from GCS   │
│  - Manual CRM import    │
└─────────────────────────┘
```

**Characteristics:**
- ✅ Automated execution
- ✅ Reliable scheduling (no human error)
- ✅ Scalable database (PostgreSQL)
- ⚠️ Still requires manual CSV download
- ❌ No real-time dashboard

**Suitable for:** Early Phase 2 (first 3 months)

**Cost Estimate:**
- Cloud SQL (db-f1-micro): ~$10-15/month
- Cloud Run: ~$5/month (minimal usage)
- Cloud Storage: ~$1/month
- **Total: ~$200/year**

#### Stage 3: Web Dashboard + API

```
┌──────────────────────────────────────────────┐
│   Google Cloud Platform                      │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │ Cloud Run (Scheduled Job)              │ │
│  │  - Runs monthly data pipeline          │ │
│  └─────────────┬──────────────────────────┘ │
│                │                             │
│  ┌─────────────▼──────────────────────────┐ │
│  │ Cloud SQL (PostgreSQL + PostGIS)       │ │
│  └─────────────┬──────────────────────────┘ │
│                │                             │
│  ┌─────────────▼──────────────────────────┐ │
│  │ Flask API (Cloud Run Service)          │ │
│  │  GET /api/leads?region=agder           │ │
│  │  GET /api/properties/{id}              │ │
│  │  POST /api/score (on-demand scoring)   │ │
│  └─────────────┬──────────────────────────┘ │
│                │                             │
│  ┌─────────────▼──────────────────────────┐ │
│  │ Web Dashboard (Cloud Run)              │ │
│  │  - Interactive map (Folium/Plotly)     │ │
│  │  - Lead list table (sortable, filters) │ │
│  │  - Analytics (lead quality metrics)    │ │
│  └────────────────────────────────────────┘ │
└────────────────┬─────────────────────────────┘
                 │
                 │ HTTPS API
                 ▼
    ┌────────────────────────┐
    │  CRM System            │
    │  (SuperOffice/HubSpot) │
    │  - Auto-imports leads  │
    │  - Daily sync          │
    └────────────────────────┘
         │
         │ Web Browser
         ▼
┌─────────────────────────┐
│  Sales Team             │
│  - Views dashboard      │
│  - Filters/sorts leads  │
│  - Clicks to CRM        │
└─────────────────────────┘
```

**Characteristics:**
- ✅ Fully automated end-to-end
- ✅ Real-time access for sales team
- ✅ CRM integration (no manual import)
- ✅ Analytics and reporting
- ✅ On-demand scoring (sales can input new property)

**Suitable for:** Phase 2 stable operation (month 3+)

**Cost Estimate:**
- Cloud SQL (db-g1-small): ~$50/month (production-grade)
- Cloud Run (API + Dashboard): ~$20/month
- Cloud Storage: ~$5/month
- **Total: ~$900/year**

**Development Effort:**
- Flask API: 3-5 days
- Web dashboard: 5-7 days
- CRM integration: 3-5 days (depends on CRM API complexity)
- Testing + deployment: 3 days
- **Total: 14-20 days** (~3-4 weeks)

### Data Refresh Frequency

**MVP Approach:**
- Manual refresh when analyst has time (ad-hoc)
- Frequency: Quarterly or when significant new data available

**Phase 2 Requirements:**
- **KILE statistics:** Annual (NVE publishes once per year)
- **N50 building data:** Quarterly (Kartverket updates 4x per year)
- **Scoring model:** Monthly (can rescore existing properties if weights change)
- **Lead list generation:** Weekly (sales team wants fresh leads)

**Recommended Schedule:**

```python
# Apache Airflow DAG (workflow scheduler)
from airflow import DAG
from datetime import datetime, timedelta

with DAG(
    'weak_grid_scoring_pipeline',
    schedule_interval='0 2 1 * *',  # 2 AM on 1st of each month
    start_date=datetime(2025, 1, 1),
    catchup=False,
) as dag:

    # Monthly tasks
    update_kile_data = BashOperator(...)     # Check NVE for new KILE file
    update_building_data = BashOperator(...) # Pull from Kartverket API
    recalculate_scores = PythonOperator(...) # Run scoring engine
    export_leads = PythonOperator(...)       # Generate top leads CSV
    update_crm = PythonOperator(...)         # Push to CRM via API
    send_notification = EmailOperator(...)   # Notify sales team

    update_kile_data >> update_building_data >> recalculate_scores
    recalculate_scores >> export_leads >> update_crm >> send_notification
```

**Orchestration Alternatives:**
- **Cloud Scheduler + Cloud Functions:** Simpler, cheaper (Google Cloud native)
- **Apache Airflow:** More powerful, better for complex dependencies
- **GitHub Actions:** Free for open source, lightweight

**Recommendation:** Start with **Cloud Scheduler + Cloud Functions** (simplest), migrate to Airflow if complexity grows.

### When to Introduce Each Component

**Decision Matrix:**

| Infrastructure Component | MVP | Phase 2 Start | Phase 2 Month 3 | Phase 3 |
|-------------------------|-----|---------------|----------------|---------|
| **SQLite Database** | ✅ Required | ✅ Still OK | ❌ Migrate away | ❌ No |
| **PostgreSQL + PostGIS** | ❌ Not needed | ⚠️ Plan migration | ✅ Deploy | ✅ Yes |
| **Cloud hosting** | ❌ Laptop OK | ⚠️ Optional | ✅ Recommended | ✅ Required |
| **Scheduled pipeline** | ❌ Manual OK | ⚠️ Nice to have | ✅ Deploy | ✅ Yes |
| **Web dashboard** | ❌ Not needed | ❌ Not yet | ⚠️ Optional | ✅ Deploy |
| **CRM API integration** | ❌ Not needed | ❌ Not yet | ⚠️ Build | ✅ Required |
| **Analytics/reporting** | ❌ Not needed | ❌ Not yet | ❌ Not yet | ✅ Deploy |

**Incremental Rollout:**

```
MVP (Week 0-4): Laptop + SQLite
├─ Goal: Validate scoring model with Agder data
├─ Output: 500 cabin leads for sales testing
└─ Cost: $0 infrastructure

Phase 2.0 (Month 1-2): National scoring + PostgreSQL
├─ Goal: Scale to national dataset (90k properties)
├─ Migrate: SQLite → PostgreSQL on Cloud SQL
├─ Output: CSV files delivered to sales via Cloud Storage
└─ Cost: ~$200/year

Phase 2.1 (Month 3-4): Scheduled automation
├─ Goal: Remove manual execution burden
├─ Deploy: Cloud Scheduler + Cloud Functions
├─ Output: Monthly automated lead generation
└─ Cost: +$100/year

Phase 2.2 (Month 5-6): CRM integration
├─ Goal: Eliminate manual CSV import step
├─ Deploy: REST API for SuperOffice/HubSpot
├─ Output: Leads auto-imported to CRM daily
└─ Cost: +$300/year (API hosting)

Phase 3 (Month 12+): Web dashboard + analytics
├─ Goal: Self-service for sales team + management reporting
├─ Deploy: Interactive dashboard + ML scoring
├─ Output: Real-time lead quality monitoring
└─ Cost: +$400/year
```

### Cost Summary

**Infrastructure Costs (Annual):**

| Stage | MVP | Phase 2.0 | Phase 2.1 | Phase 2.2 | Phase 3 |
|-------|-----|-----------|-----------|-----------|---------|
| Database | $0 | $200 | $600 | $600 | $900 |
| Compute | $0 | $0 | $100 | $300 | $500 |
| Storage | $0 | $50 | $50 | $50 | $100 |
| **Total/year** | **$0** | **$250** | **$750** | **$950** | **$1,500** |
| **Total/month** | **$0** | **$21** | **$63** | **$79** | **$125** |

**Development Costs (One-Time):**

| Component | Effort | Cost @ 1,200 NOK/hr |
|-----------|--------|---------------------|
| PostgreSQL migration | 3 days | 28,800 NOK |
| Cloud deployment setup | 2 days | 19,200 NOK |
| Scheduled pipeline | 3 days | 28,800 NOK |
| CRM API integration | 5 days | 48,000 NOK |
| Web dashboard | 7 days | 67,200 NOK |
| **Total development** | **20 days** | **192,000 NOK** |

**Phase 2 Total Budget:**
- Development: 192,000 NOK
- Infrastructure (Year 1): 1,500 NOK
- Kartverket API agreement: 10,000 NOK
- Contingency (15%): 30,525 NOK
- **Total: ~234,000 NOK** (within 500k budget comfortably)

### Recommendations

**✅ MVP: Stay Laptop-Based**
- Rationale: Fastest path to validation, zero infrastructure cost
- Acceptable: Manual execution acceptable for 2-4 week MVP

**⚠️ Phase 2.0: Immediate PostgreSQL Migration**
- Rationale: 90k properties will strain SQLite
- Timing: Month 1 of Phase 2 (before national data ingestion)
- Priority: HIGH (prevents performance bottleneck)

**📅 Phase 2.1: Automate After 2 Months**
- Rationale: Prove model value before investing in automation
- Timing: After sales team validates lead quality
- Priority: MEDIUM (quality of life improvement)

**🔗 Phase 2.2: CRM Integration After 4 Months**
- Rationale: Wait until lead generation is stable and proven
- Timing: After scoring model has been tuned based on feedback
- Priority: MEDIUM (efficiency gain, not critical path)

**📊 Phase 3: Dashboard is Phase 3 Feature**
- Rationale: Sales team can use CRM for now, dashboard is "nice to have"
- Timing: 12+ months (after ML model is ready)
- Priority: LOW (defer until proven value)

---

## 6. TEAM & PROCESS SCALING

### Current State (MVP)
- **Team composition:** 1-2 developers (generalists)
- **Skills required:** Python, geospatial analysis, data cleaning
- **Timeline:** 2-4 weeks
- **Knowledge transfer:** Minimal (single developer retains all context)
- **Maintenance burden:** Low (run script quarterly, minimal updates)

### Target State (Phase 2)
- **Team composition:** ?
- **Skills required:** Python, geospatial, ML, DevOps, data engineering
- **Timeline:** 2-3 months
- **Knowledge transfer:** Critical (must document for handoff/future team)
- **Maintenance burden:** Higher (monthly data updates, model tuning, CRM integration)

### Team Composition Recommendations

#### MVP Team (2-4 weeks)

**Required Roles:**
- **1x Data Engineer / Geospatial Analyst**
  - Skills: Python, GeoPandas, spatial analysis, data cleaning
  - Responsibilities:
    - Download and process N50 building data
    - Implement distance calculations (power lines)
    - Build scoring algorithm
    - Generate visualizations (Folium maps)
  - Time commitment: Full-time (2-4 weeks)

**Optional Roles:**
- **0.5x Domain Expert (Norsk Solkraft sales lead)**
  - Skills: Understanding of weak grid customers, market knowledge
  - Responsibilities:
    - Validate scoring weights
    - Review generated leads for quality
    - Provide feedback on false positives/negatives
  - Time commitment: Part-time (2-4 hours/week for reviews)

**Total Team Size:** 1-1.5 FTE

#### Phase 2 Team (2-3 months)

**Required Roles:**

**1x Lead Data Engineer (Full-time)**
- Skills: Python, pandas, GeoPandas, SQL, PostGIS
- Responsibilities:
  - PostgreSQL migration
  - Kartverket API integration
  - National data processing pipeline
  - Scoring model implementation (3 property types)
  - Quality assurance and validation
- Time commitment: Full-time (3 months)
- Cost: 360k NOK (120 days × 3,000 NOK/day)

**1x DevOps / Backend Engineer (Part-time)**
- Skills: Cloud platforms (GCP), Docker, API development (Flask/FastAPI)
- Responsibilities:
  - Cloud infrastructure setup (Cloud SQL, Cloud Run)
  - Scheduled pipeline automation (Cloud Scheduler)
  - CRM API integration (SuperOffice/HubSpot)
  - Monitoring and logging
- Time commitment: Part-time (30-40 days over 3 months)
- Cost: 100k NOK (35 days × 2,800 NOK/day)

**0.5x Domain Expert / Product Owner (Part-time)**
- Skills: Market knowledge, sales process understanding, requirement definition
- Responsibilities:
  - Define regional scoring variations
  - Validate lead quality across property types
  - CRM integration requirements
  - Sales team training
- Time commitment: Part-time (10-15 hours/week)
- Cost: Typically internal Norsk Solkraft resource (no external cost)

**Optional (Highly Recommended):**

**0.3x ML Engineer (Consulting, ad-hoc)**
- Skills: Scikit-learn, model evaluation, feature engineering
- Responsibilities:
  - Design data collection infrastructure for future ML
  - Advise on feature engineering for rule-based model
  - Prepare ML training pipeline (Phase 3 readiness)
- Time commitment: Consulting basis (3-5 days over Phase 2)
- Cost: 25k NOK (5 days × 5,000 NOK/day for specialist)

**Total Team Size:** 1.8-2.3 FTE over 3 months

**Total Phase 2 Labor Cost:** ~485k NOK (within 500k budget)

#### Phase 3 Team (Ongoing maintenance + ML)

**Required Roles:**

**0.5x Data Engineer (Ongoing)**
- Responsibilities:
  - Monthly data pipeline monitoring
  - Quarterly data source updates (NVE KILE, Kartverket)
  - Scoring model tuning based on sales feedback
  - Bug fixes and minor enhancements
- Time commitment: Part-time (2-3 days/month)
- Cost: ~100k NOK/year

**0.3x ML Engineer (Ongoing)**
- Responsibilities:
  - ML model training (quarterly retraining)
  - Model performance monitoring
  - A/B testing rule-based vs. ML
  - Feature engineering and optimization
- Time commitment: Ad-hoc (5-7 days/quarter)
- Cost: ~100k NOK/year

**0.2x DevOps (Ongoing)**
- Responsibilities:
  - Infrastructure monitoring (uptime, performance)
  - Security updates
  - Cost optimization
- Time commitment: Ad-hoc (1-2 days/month)
- Cost: ~50k NOK/year

**Total Ongoing Cost:** ~250k NOK/year (maintenance + continuous improvement)

### Knowledge Transfer Requirements

**Critical Knowledge Areas:**

1. **Data Sources & Acquisition**
   - Where to download NVE KILE data (URL, format, update frequency)
   - Kartverket API credentials and usage
   - N50 building type codes and classifications
   - Grid company mapping table

2. **Scoring Model Logic**
   - Weight rationale for each factor
   - Regional calibration adjustments
   - Property type segmentation rules
   - Threshold values and why they were chosen

3. **Code Architecture**
   - Database schema (tables, indexes, relationships)
   - Pipeline execution order (dependencies)
   - Geospatial query optimization techniques
   - Error handling and logging

4. **Infrastructure**
   - Cloud account access and permissions
   - Deployment procedures
   - Monitoring and alerting setup
   - Cost management and optimization

5. **Business Logic**
   - Definition of "weak grid" (validated with sales team)
   - Lead prioritization criteria
   - CRM integration workflow
   - Sales team feedback loop

**Documentation Deliverables:**

```
/docs
├── README.md                      # Project overview, quick start
├── architecture/
│   ├── data_model.md             # Database schema, entity relationships
│   ├── scoring_algorithm.md      # Detailed scoring logic with examples
│   └── infrastructure.md         # Cloud setup, deployment guide
├── data_sources/
│   ├── nve_kile_guide.md         # How to download and process KILE data
│   ├── kartverket_api.md         # API credentials, usage examples
│   └── grid_company_mapping.md   # Municipality → grid company lookup
├── operations/
│   ├── deployment.md             # Step-by-step deployment to production
│   ├── monitoring.md             # How to check pipeline health
│   ├── troubleshooting.md        # Common issues and solutions
│   └── monthly_tasks.md          # Routine maintenance checklist
└── development/
    ├── setup_environment.md      # Conda env setup, dependencies
    ├── testing.md                # How to run tests, validation procedures
    └── contributing.md           # Code standards, PR process
```

**Documentation Timeline:**
- MVP: Minimal (README + comments in code)
- Phase 2: Comprehensive (20-30 pages of docs)
- Effort: 3-5 days (included in Phase 2 timeline)

### Maintenance Workload Estimates

**Monthly Tasks (Steady State - Phase 2+):**

| Task | Frequency | Time Required | Responsibility |
|------|-----------|---------------|----------------|
| Check data pipeline execution | Monthly | 30 minutes | Data Engineer |
| Review lead quality metrics | Monthly | 1 hour | Product Owner |
| Update scoring weights (if needed) | Quarterly | 2 hours | Data Engineer + Domain Expert |
| Download new KILE data (when available) | Annually | 1 hour | Data Engineer |
| Kartverket data refresh | Quarterly | 30 minutes (automated) | System (monitored by DevOps) |
| CRM sync monitoring | Weekly | 15 minutes | DevOps |
| Infrastructure cost review | Monthly | 30 minutes | DevOps |
| **Total maintenance** | - | **~8 hours/month** | - |

**Ad-hoc Tasks (Variable):**

| Task | Frequency | Time Required | Trigger |
|------|-----------|---------------|---------|
| Debug data quality issues | 2-3x/year | 2-4 hours | Sales team reports bad leads |
| Regional scoring calibration | 1-2x/year | 4-6 hours | Expansion to new region |
| CRM integration updates | 1x/year | 2-3 days | CRM system upgrades |
| Infrastructure upgrades | 1x/year | 1-2 days | Security patches, migrations |
| ML model training (Phase 3) | Quarterly | 2-3 days | New conversion data available |

**Annual Maintenance Budget:**
- Routine maintenance: 100 hours/year × 1,200 NOK/hr = **120k NOK/year**
- Ad-hoc tasks: 15 days/year × 8 hrs × 1,200 NOK/hr = **144k NOK/year**
- **Total: ~250k NOK/year** (consistent with Phase 3 team estimate)

### Recommendations

**✅ MVP: Keep Team Minimal**
- 1 generalist data engineer sufficient
- Bring in domain expert for validation only
- No formal documentation needed (code comments OK)

**👥 Phase 2: Expand to 2-person Core Team**
- Primary: Data engineer (full-time for 3 months)
- Secondary: DevOps engineer (part-time, infrastructure setup)
- Advisory: ML engineer (3-5 days consulting for Phase 3 prep)

**📚 Phase 2: Invest in Documentation**
- Budget 3-5 days for comprehensive docs
- Critical for knowledge transfer and maintenance
- Treat as mandatory deliverable (not optional)

**🔄 Phase 3: Establish Maintenance Team**
- 0.5 FTE data engineer (ongoing)
- 0.3 FTE ML engineer (quarterly retraining)
- 0.2 FTE DevOps (monitoring, security)
- **Total: ~1 FTE distributed across specialties**

**💡 Recommendation: Train Internal Team**
- Avoid full dependency on external consultants
- Train 1-2 Norsk Solkraft employees during Phase 2
- Knowledge retention critical for long-term sustainability
- Budget: +2 weeks for knowledge transfer training

---

## 7. DATA QUALITY SCALING

### Current State (MVP)
- **Manual QA:** Developer visually inspects sample of generated leads
- **Validation method:** Compare against existing Norsk Solkraft customers in Agder
- **Error handling:** Ad-hoc debugging when issues found
- **Data quality issues:** Low impact (15k properties, small region)

### Target State (Phase 2)
- **Automated QA:** Systematic validation rules for 90k properties
- **Validation method:** Statistical validation + multi-region testing
- **Error handling:** Automated anomaly detection and alerts
- **Data quality issues:** High impact (6x data volume, critical for national rollout)

### Data Quality Challenges at Scale

#### 1. Source Data Quality Variations

**N50 Building Data (Kartverket):**

**Quality Variation by Region:**
| Region Type | Data Completeness | Coordinate Accuracy | Building Type Accuracy |
|-------------|------------------|---------------------|----------------------|
| **Urban areas** | 95-98% | ±5 meters | 90-95% |
| **Rural lowlands** | 90-95% | ±10 meters | 85-90% |
| **Mountain/fjord areas** | 80-90% | ±20 meters | 70-80% |
| **Remote Arctic** | 70-85% | ±50 meters | 60-75% |

**Observed Issues:**
- **Missing buildings:** Remote cabins not in official registry (built pre-digital era)
- **Wrong building type:** Cabin classified as "anneks" (secondary structure) instead of "fritidsbolig"
- **Outdated coordinates:** GPS drift over years, not updated in Matrikkelen
- **Demolished buildings:** Still in database (no removal process)

**Impact on Scoring:**
- False negatives: Real cabins with weak grid missed (not in database)
- False positives: Demolished buildings scored as leads
- Misclassification: Rural home scored as cabin (wrong segment)

**Mitigation Strategy:**
```python
# Validation rules for N50 data
def validate_building_record(building):
    """
    Flag potentially bad records
    """
    issues = []

    # 1. Coordinate sanity check (must be in Norway)
    if not (57 <= building.latitude <= 71 and 4 <= building.longitude <= 31):
        issues.append("CRITICAL: Coordinates outside Norway")

    # 2. Building age consistency
    if building.building_year < 1800 or building.building_year > 2025:
        issues.append("WARNING: Implausible building year")

    # 3. Floor area plausibility
    if building.floor_area_m2 < 10 or building.floor_area_m2 > 500:
        issues.append("WARNING: Unusual floor area for cabin")

    # 4. Duplicate detection (same lat/lon)
    if count_buildings_at_location(building.latitude, building.longitude) > 1:
        issues.append("WARNING: Potential duplicate building")

    return issues
```

#### 2. KILE Data Quality Issues

**Known Problems:**
- **New grid companies:** Merged or split companies have inconsistent naming
- **Missing years:** Some companies don't report KILE for all years
- **Outliers:** Single severe weather event skews annual SAIDI (e.g., 2023 storm in Northern Norway)
- **Definition changes:** NVE occasionally updates KILE calculation methodology

**Example:**
```
# Problem: Grid company merger
Year 2022: "BKK Nett AS" (SAIDI: 82 min)
Year 2023: "Altibox Nett AS" (acquired BKK)
Result: Can't find "BKK Nett AS" in 2023 KILE data → missing score

# Solution: Maintain company mapping table
GRID_COMPANY_ALIASES = {
    "BKK Nett AS": "Altibox Nett AS",  # Merged 2023
    "Fortum Distribution AS": "Eidsiva Nett AS",  # Rebranded 2021
}
```

**Mitigation Strategy:**
```python
# Handle missing KILE data gracefully
def get_kile_score(grid_company_name, year=2023):
    """
    Fetch KILE with fallback strategy
    """
    # 1. Try exact match
    kile_data = kile_df[kile_df['company'] == grid_company_name]
    if not kile_data.empty:
        return kile_data.iloc[0]['SAIDI']

    # 2. Try aliases (mergers/rebrands)
    if grid_company_name in GRID_COMPANY_ALIASES:
        alt_name = GRID_COMPANY_ALIASES[grid_company_name]
        kile_data = kile_df[kile_df['company'] == alt_name]
        if not kile_data.empty:
            return kile_data.iloc[0]['SAIDI']

    # 3. Fallback: Use regional average
    region = get_region_for_company(grid_company_name)
    regional_avg = kile_df[kile_df['region'] == region]['SAIDI'].mean()

    logging.warning(f"Using regional average KILE for {grid_company_name}")
    return regional_avg
```

#### 3. Power Line Data Quality

**NVE Atlas Issues:**
- **Incomplete rural coverage:** Private cabin area lines not registered
- **Outdated data:** New power lines take 6-12 months to appear in NVE Atlas
- **Missing low-voltage lines:** Only transmission lines (>22 kV) mapped, not local distribution

**Impact:**
- **Overestimated distances:** Cabin shows 2 km to nearest power line, but local distribution line exists at 200m
- **Result:** False positives (cabin scored as weak grid when actually has adequate connection)

**Mitigation Strategy:**
```python
# Distance to power line with confidence scoring
def calculate_power_line_distance_with_confidence(building_point, power_lines_gdf):
    """
    Add confidence level based on data completeness
    """
    distance_m = power_lines_gdf.distance(building_point).min() * 111320

    # Confidence factors
    if distance_m < 500:
        confidence = "HIGH"  # Close to known line
    elif 500 <= distance_m < 2000:
        confidence = "MEDIUM"  # Could have unmapped local line
    else:
        confidence = "LOW"  # Very remote, but NVE data may be incomplete

    return {
        "distance_m": distance_m,
        "confidence": confidence,
        "note": "Distance to nearest REGISTERED power line (may be underestimate)"
    }
```

#### 4. Error Propagation at Scale

**Problem:** If 5% of MVP data is bad, what's the impact nationally?

**MVP (15k properties):**
- 5% data quality issues = 750 bad records
- Generates 500 top leads
- Estimated bad leads: ~25 (5% × 500)
- **Acceptable:** Sales team can handle 25 false positives

**National (90k properties):**
- 5% data quality issues = 4,500 bad records
- Generates 2,000 top leads (targeting more regions)
- Estimated bad leads: ~100 (5% × 2,000)
- **Problematic:** Sales team wastes significant time on bad leads

**Compounding Errors:**
- Building coordinate error (±50m) + Power line incompleteness → Distance calculation off by 200-500m
- Wrong building type + Outdated KILE data → Lead scored in wrong segment
- **Result:** Error compounds through scoring pipeline

**Mitigation: Confidence Scoring**

```python
# Add confidence level to each lead
def calculate_lead_confidence(property_data):
    """
    Estimate reliability of weak grid score
    """
    confidence_score = 100  # Start at 100%

    # Penalize based on data quality flags
    if property_data['coordinate_accuracy'] == "LOW":
        confidence_score -= 15

    if property_data['power_line_distance_confidence'] == "MEDIUM":
        confidence_score -= 10
    elif property_data['power_line_distance_confidence'] == "LOW":
        confidence_score -= 25

    if property_data['kile_data_source'] == "REGIONAL_AVERAGE":
        confidence_score -= 20

    if property_data['building_type_confidence'] == "INFERRED":
        confidence_score -= 15

    # Confidence categories
    if confidence_score >= 80:
        return "HIGH"
    elif confidence_score >= 60:
        return "MEDIUM"
    else:
        return "LOW"

# Filter leads by confidence
high_confidence_leads = leads_df[leads_df['confidence'] == "HIGH"]
```

**Benefit:** Sales team can prioritize high-confidence leads, reducing wasted effort.

### Automated Validation Rules

**Implement Systematic Quality Checks:**

```python
# Data quality validation pipeline
def validate_national_dataset(buildings_gdf):
    """
    Comprehensive data quality checks
    """
    validation_report = {
        "total_records": len(buildings_gdf),
        "issues_found": [],
    }

    # 1. Geographic bounds check
    out_of_bounds = buildings_gdf[
        (buildings_gdf.latitude < 57) | (buildings_gdf.latitude > 71) |
        (buildings_gdf.longitude < 4) | (buildings_gdf.longitude > 31)
    ]
    if len(out_of_bounds) > 0:
        validation_report["issues_found"].append({
            "severity": "CRITICAL",
            "count": len(out_of_bounds),
            "issue": "Coordinates outside Norway",
        })

    # 2. Missing critical fields
    missing_building_type = buildings_gdf[buildings_gdf['building_type'].isna()]
    if len(missing_building_type) > 0:
        validation_report["issues_found"].append({
            "severity": "HIGH",
            "count": len(missing_building_type),
            "issue": "Missing building type",
        })

    # 3. Duplicate detection
    duplicates = buildings_gdf[
        buildings_gdf.duplicated(subset=['latitude', 'longitude'], keep=False)
    ]
    if len(duplicates) > 0:
        validation_report["issues_found"].append({
            "severity": "MEDIUM",
            "count": len(duplicates),
            "issue": "Duplicate coordinates",
        })

    # 4. Statistical outliers
    z_scores = np.abs(stats.zscore(buildings_gdf['dist_to_power_line_m']))
    outliers = buildings_gdf[z_scores > 3]  # More than 3 std deviations
    if len(outliers) > 10:
        validation_report["issues_found"].append({
            "severity": "LOW",
            "count": len(outliers),
            "issue": "Statistical outliers in power line distance",
        })

    # 5. Regional consistency check
    regional_stats = buildings_gdf.groupby('county')['weak_grid_score'].agg(['mean', 'std'])
    anomalous_regions = regional_stats[
        (regional_stats['mean'] < 20) | (regional_stats['mean'] > 80)
    ]
    if len(anomalous_regions) > 0:
        validation_report["issues_found"].append({
            "severity": "HIGH",
            "count": len(anomalous_regions),
            "issue": f"Anomalous scoring in regions: {list(anomalous_regions.index)}",
        })

    return validation_report
```

**Automated Alerts:**
```python
# Send alerts for critical data quality issues
def send_data_quality_alert(validation_report):
    """
    Alert data engineer if critical issues detected
    """
    critical_issues = [
        issue for issue in validation_report["issues_found"]
        if issue["severity"] == "CRITICAL"
    ]

    if critical_issues:
        # Send email/Slack notification
        send_notification(
            to="data-team@norsksolkraft.no",
            subject="⚠️ Data Quality Alert: Critical Issues Detected",
            message=f"Found {len(critical_issues)} critical issues in latest data refresh. Review required before lead generation."
        )
```

### Acceptable Error Rates

**Recommended Thresholds:**

| Error Type | Acceptable Rate | Action if Exceeded |
|------------|----------------|-------------------|
| **Missing coordinates** | <1% | BLOCK: Don't generate leads until fixed |
| **Out-of-bounds coordinates** | <0.5% | BLOCK: Critical data corruption |
| **Missing building type** | <3% | WARN: Exclude from scoring, notify team |
| **Duplicate records** | <2% | WARN: Auto-deduplicate, log for review |
| **Missing KILE data** | <5% | ALLOW: Use regional average fallback |
| **Power line distance outliers** | <10% | ALLOW: Flag low confidence |
| **Overall bad leads (sales feedback)** | <15% | TUNE: Adjust scoring model |

**Validation Gate:**
```python
# Block lead generation if critical errors exceed threshold
def validate_and_proceed(buildings_gdf):
    """
    Quality gate before lead generation
    """
    validation = validate_national_dataset(buildings_gdf)

    critical_count = sum(
        issue["count"] for issue in validation["issues_found"]
        if issue["severity"] == "CRITICAL"
    )

    critical_rate = critical_count / validation["total_records"]

    if critical_rate > 0.01:  # 1% threshold
        raise DataQualityException(
            f"Critical error rate {critical_rate:.1%} exceeds 1% threshold. "
            f"Fix data quality issues before proceeding."
        )

    # Log warnings but proceed
    high_count = sum(
        issue["count"] for issue in validation["issues_found"]
        if issue["severity"] == "HIGH"
    )
    if high_count > 0:
        logging.warning(f"Proceeding with {high_count} high-severity warnings")

    return validation
```

### Recommendations

**✅ MVP: Manual QA is Sufficient**
- 15k properties small enough for spot-checking
- Validate against 20-30 existing customers
- No automated validation needed

**⚠️ Phase 2: Implement Automated Validation**
- Build comprehensive validation pipeline (budget 2-3 days)
- Set up automated alerts for critical issues
- Establish acceptable error rate thresholds
- **Priority: HIGH** (prevents scaling disasters)

**📊 Phase 2: Add Confidence Scoring**
- Calculate confidence level for each lead
- Allow sales team to filter by confidence
- Track which confidence levels convert best
- **Priority: MEDIUM** (quality of life, not critical)

**🔄 Phase 3: Continuous Quality Monitoring**
- Dashboard showing data quality metrics over time
- Automated anomaly detection (regional scoring shifts)
- Sales feedback loop (mark bad leads for retraining)
- **Priority: LOW** (nice to have, defer to Phase 3)

**💡 Key Insight:** Data quality at scale requires PROACTIVE validation, not reactive debugging.

---

## 8. CRITICAL SUCCESS FACTORS & RISK ASSESSMENT

### Scale-Up Success Factors

**1. Early PostgreSQL Migration (CRITICAL)**
- **Why:** SQLite will bottleneck at ~40k properties
- **When:** Month 1 of Phase 2 (before national data ingestion)
- **Risk if delayed:** Project stalls due to performance issues
- **Mitigation:** Include PostgreSQL migration in Phase 2 kickoff

**2. Kartverket API Agreement (CRITICAL)**
- **Why:** Manual national data acquisition is impractical
- **When:** Apply at Phase 2 start (2-4 week approval process)
- **Risk if delayed:** National rollout blocked for 1+ month
- **Mitigation:** Start application IMMEDIATELY upon Phase 2 funding approval

**3. Regional Scoring Calibration (HIGH)**
- **Why:** Agder model may not generalize to Finnmark/Arctic
- **When:** Month 2 of Phase 2 (after initial national scoring)
- **Risk if skipped:** Poor lead quality in non-Southern regions
- **Mitigation:** Budget 2-3 days for regional testing

**4. Data Quality Automation (HIGH)**
- **Why:** 90k properties = 6x error volume without systematic checks
- **When:** Month 1 of Phase 2 (parallel with PostgreSQL migration)
- **Risk if skipped:** Sales team overwhelmed with bad leads
- **Mitigation:** Build validation pipeline early (before lead generation)

**5. Sales Team Training (MEDIUM)**
- **Why:** National leads span 3 property types with different pitches
- **When:** Month 3 of Phase 2 (before CRM integration)
- **Risk if skipped:** Low conversion rate despite good leads
- **Mitigation:** Budget 2 days for training materials + workshop

### Risk Assessment Matrix

| Risk | Probability | Impact | Severity | Mitigation |
|------|------------|--------|----------|-----------|
| **SQLite performance degradation at 50k+ properties** | HIGH | HIGH | 🔴 **CRITICAL** | Migrate to PostgreSQL in Month 1 |
| **Kartverket API approval delayed >4 weeks** | MEDIUM | HIGH | 🟡 **HIGH** | Apply early, have manual fallback plan |
| **Regional scoring model fails in Arctic regions** | MEDIUM | MEDIUM | 🟡 **HIGH** | Test on sample, create regional profiles |
| **Data quality issues exceed 15% bad leads** | MEDIUM | MEDIUM | 🟡 **HIGH** | Automated validation + confidence scoring |
| **CRM integration blocked by IT policies** | LOW | MEDIUM | 🟢 **MEDIUM** | Start API access approval early |
| **Grid company boundary mapping errors** | MEDIUM | LOW | 🟢 **MEDIUM** | Use municipality fallback, validate sample |
| **Infrastructure costs exceed budget** | LOW | LOW | 🟢 **LOW** | Start with minimal infra, scale gradually |
| **ML model insufficient training data after 12 months** | HIGH | LOW | 🟢 **LOW** | Keep rule-based as fallback, not critical |

### What Could Go Wrong During Scale-Up?

**Scenario 1: "The Big Data Surprise"**
- **Problem:** National dataset processing takes 3 hours instead of expected 30 minutes
- **Cause:** Underestimated geospatial query complexity (2.7B distance calculations)
- **Symptom:** Pipeline timeouts, manual intervention required for each run
- **Impact:** Monthly lead generation becomes unreliable
- **Prevention:**
  - Benchmark full national query on PostgreSQL BEFORE committing to architecture
  - Implement chunked processing (10k property batches) as backup
  - Add query timeout alerts (email if processing >1 hour)

**Scenario 2: "The GDPR Complaint"**
- **Problem:** Customer complains to Datatilsynet about unsolicited marketing
- **Cause:** Lead list includes personally identifiable addresses, used for direct contact
- **Symptom:** Datatilsynet investigation, potential fines
- **Impact:** Project shutdown, legal costs, reputational damage
- **Prevention:**
  - ✅ Use postal code aggregation (NEVER individual addresses in marketing)
  - ✅ Get legal GDPR review before Phase 2 launch (budget 50k NOK)
  - ✅ Implement opt-out mechanism in all marketing materials
  - ✅ Document "legitimate interest" justification for data processing

**Scenario 3: "The Regional Mismatch"**
- **Problem:** Leads in Northern Norway have 5% conversion vs. 15% in Agder
- **Cause:** Scoring model tuned for Southern Norway climate/terrain
- **Symptom:** Sales team frustrated, low ROI in northern regions
- **Impact:** Phase 2 ROI targets missed, management loses confidence
- **Prevention:**
  - Test scoring model on sample of 100 properties per region before full rollout
  - Create regional scoring profiles (Northern, Southern, Coastal, Inland)
  - Set region-specific conversion expectations (not uniform 10%)

**Scenario 4: "The API Rate Limit"**
- **Problem:** Kartverket API throttles requests after 1,000 buildings fetched
- **Cause:** Didn't read API terms of service carefully
- **Symptom:** Data ingestion fails halfway through, incomplete dataset
- **Impact:** Delayed launch, need alternative data acquisition method
- **Prevention:**
  - Read Kartverket API documentation thoroughly (especially rate limits)
  - Implement exponential backoff and retry logic
  - Budget for premium API tier if needed (cost-benefit analysis)

**Scenario 5: "The Sales Team Rebellion"**
- **Problem:** Sales team ignores generated leads, claims they're "not useful"
- **Cause:** Leads don't match sales team's intuition or existing workflows
- **Symptom:** Zero conversions despite technically correct scoring
- **Impact:** Project deemed failure, investment wasted
- **Prevention:**
  - Involve sales team from DAY 1 (validate MVP leads with them)
  - Collect continuous feedback (weekly lead quality reviews in Phase 2)
  - Provide training on how to use leads effectively
  - Allow manual override (sales can adjust lead priority)

### Recommendations for Risk Mitigation

**✅ Phase 2 Kickoff Actions (First Week):**
1. Apply for Kartverket API agreement (don't wait)
2. Set up PostgreSQL Cloud SQL instance (test migration immediately)
3. Schedule legal GDPR review (get on lawyer's calendar)
4. Benchmark national-scale geospatial queries (validate architecture)
5. Conduct sales team workshop (set expectations, gather requirements)

**⚠️ Phase 2 Monthly Check-ins:**
- Week 4: PostgreSQL migration complete? (go/no-go decision)
- Week 8: Regional scoring tested? (calibration needed?)
- Week 12: Sales team feedback on lead quality? (model tuning needed?)

**🚨 Red Flags (Stop and Reassess):**
- If data quality validation fails >20% of records → Fix data sources before proceeding
- If PostgreSQL queries take >30 minutes → Rearchitect before scaling further
- If sales team conversion rate <5% after 3 months → Scoring model needs major revision
- If infrastructure costs exceed 2x budget → Optimize or reduce scope

---

## 9. FINAL RECOMMENDATION

### Is Phase 2 National Scaling Feasible?

**Answer: ✅ YES - With Strategic Execution**

The MVP architecture is fundamentally sound for national scaling, but requires **3 critical upgrades** at specific thresholds:

1. **Database Migration (40k+ properties):** SQLite → PostgreSQL+PostGIS
2. **Data Automation (National rollout):** Manual downloads → Kartverket API
3. **Quality Assurance (90k properties):** Ad-hoc checks → Automated validation

### Would You Change MVP Design Knowing National Scale is Needed?

**Answer: ⚠️ MINOR CHANGES ONLY**

**✅ Keep in MVP:**
- SQLite (right choice for 15k properties, fastest MVP path)
- Rule-based scoring (no training data available, explainable to sales)
- pandas/GeoPandas (mature, well-documented, team already knows)
- Manual data acquisition (1 county is manageable, automation overkill)

**🔧 Add to MVP (Preparation for Scale):**

1. **Modular Scoring Functions**
```python
# Design MVP scoring to be property-type agnostic
def calculate_score(property_data, scoring_profile):
    """
    Generic scoring function that accepts profile parameter
    """
    # In MVP: Only cabin profile exists
    # In Phase 2: Add farm and rural_home profiles
    pass
```

2. **PostgreSQL Migration Script (Dormant)**
```python
# Include in MVP repo, but don't execute
# migrations/sqlite_to_postgres.py

def migrate_to_postgres():
    """
    One-time migration script (run in Phase 2)
    """
    # Export SQLite → CSV → PostgreSQL
    pass
```

3. **Confidence Scoring Infrastructure**
```python
# Add data quality flags in MVP
buildings_df['data_quality_confidence'] = calculate_confidence(...)

# Allows Phase 2 to filter by confidence without refactoring
```

4. **Configuration File for Scoring Weights**
```yaml
# config/scoring_weights.yaml
cabin_scoring:
  geographic_weight: 0.40
  grid_weight: 0.30
  property_weight: 0.30
  distance_to_power_line_thresholds: [500, 1000]

# Allows Phase 2 to add farm_scoring, rural_home_scoring easily
```

**Estimated Additional MVP Effort:** +2 days (10% increase)

**Benefit:** Smoother Phase 2 transition, reduced refactoring

### Should MVP Be Built Differently?

**Common Mistake: Over-Engineer for Future Scale**

❌ **Don't do this in MVP:**
- Start with PostgreSQL (slower MVP development, zero benefit at 15k scale)
- Build CRM API integration (no CRM requirements defined yet)
- Implement ML model (no training data exists)
- Create web dashboard (sales team hasn't validated lead quality yet)

**Why:** These add 3-4 weeks to MVP timeline with NO validation value.

✅ **Do this instead:**
- Build simplest possible MVP (SQLite, rule-based, manual, CSV outputs)
- Validate scoring model with sales team (prove concept)
- THEN invest in scalability infrastructure (Phase 2)

**Key Principle:** **PROVE VALUE BEFORE SCALING**

### Phase 2 Execution Roadmap

**Month 1: Infrastructure & Data**
- Week 1-2: PostgreSQL migration + Kartverket API setup
- Week 3-4: National data ingestion + validation pipeline

**Month 2: Scoring & Segmentation**
- Week 1-2: Implement 3-segment scoring (cabin, farm, rural home)
- Week 3-4: Regional calibration + quality testing

**Month 3: Automation & Integration**
- Week 1-2: Scheduled pipeline (Cloud Scheduler)
- Week 3-4: CRM API integration + sales training

**Deliverables:**
- 90k properties scored and ranked
- 2,000 high-priority leads (national)
- Automated monthly lead generation
- CRM-integrated workflow

**Budget:**
- Development: 192k NOK (20 days × 3 FTE)
- Infrastructure: 10k NOK (year 1)
- Data agreements: 10k NOK (Kartverket)
- Legal review: 50k NOK (GDPR compliance)
- Contingency: 30k NOK
- **Total: ~290k NOK** (vs. 500k budget → ✅ **Well under budget**)

### Critical Path Items

**Must Start Immediately (Week 1 of Phase 2):**
1. ✅ Kartverket API application (2-4 week approval time)
2. ✅ Legal GDPR review (2-3 week turnaround)
3. ✅ PostgreSQL Cloud SQL setup (1 day)

**Can Start Later:**
- CRM integration (Month 3, after scoring validated)
- Web dashboard (Phase 3, not critical path)
- ML model (Phase 3, requires 12+ months of conversion data)

### Success Metrics

**Phase 2 KPIs:**
- **Technical:** Process 90k properties in <15 minutes
- **Quality:** <15% bad leads (sales team feedback)
- **Business:** Generate 2,000 qualified leads nationally
- **Efficiency:** 80% automation (minimal manual intervention)
- **Reliability:** 95% uptime for automated pipeline

**Go/No-Go Decision Point (Month 2):**
- If technical performance meets targets → Continue to automation (Month 3)
- If lead quality <60% recall → Pause, retune scoring model
- If infrastructure costs >2x budget → Reassess architecture

---

## CONCLUSION

**National scaling from 15k to 90k properties is HIGHLY FEASIBLE** with the proposed MVP architecture as foundation.

**Key Insights:**
1. **Data volume (6x):** Manageable with PostgreSQL migration at 40k threshold
2. **Geographic coverage (11x):** API automation reduces effort to 1.5x (not 11x)
3. **Property diversity (3 types):** Segmented scoring adds 1.8x complexity (manageable)
4. **Infrastructure:** Incremental upgrades prevent premature optimization

**Critical Success Factors:**
- Early PostgreSQL migration (Month 1)
- Kartverket API agreement (apply immediately)
- Automated data quality validation (prevent scale-up disasters)
- Sales team involvement (continuous feedback loop)

**Budget Impact:**
- MVP: 200k NOK (on track)
- Phase 2: 290k NOK (58% of 500k budget)
- Phase 3: 250k NOK/year (ongoing maintenance + ML)

**Timeline:**
- MVP: 2-4 weeks ✅
- Phase 2: 3 months ✅
- Phase 3: 12+ months (continuous improvement)

**Recommendation:** **PROCEED WITH MVP AS DESIGNED** → Validate scoring model → Execute Phase 2 national rollout with identified architectural upgrades.

---

**Document Status:** Ready for decision-making
**Next Actions:**
1. Approve MVP budget (200k NOK)
2. Validate MVP lead quality with sales team (2-4 weeks)
3. If validation successful (recall >60%), approve Phase 2 budget (290k NOK)
4. Initiate Kartverket API application and GDPR legal review

**Questions for Stakeholders:**
1. Is 15% bad lead rate acceptable for national rollout? (Or require <10%?)
2. Should we start with cabin-only nationally, or launch all 3 segments simultaneously?
3. Is CRM API integration mandatory for Phase 2, or acceptable to defer to Phase 3?
4. What conversion rate threshold triggers ML model investment? (Current plan: after 12 months + 300 labeled examples)

---

**End of Scalability Assessment**
