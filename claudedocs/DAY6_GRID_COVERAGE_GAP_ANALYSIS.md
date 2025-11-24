# Grid Company Service Area Coverage Gap Analysis

**Date**: 2025-11-22
**Status**: 🔴 CRITICAL BLOCKER - NVE data incomplete for southern Agder

---

## Summary

Successfully downloaded and loaded 88 grid company service areas from NVE, but discovered **critical geographic coverage gap** preventing cabin-to-grid company assignment via spatial join.

**Result:** 0% of cabins matched to grid companies due to missing service area coverage in southern Agder region where 73% of cabins are located.

---

## What Was Accomplished

### 1. Downloaded Official Service Area Data ✅
- **Script Created**: `scripts/08_download_grid_company_areas.sh`
- **Source**: NVE ArcGIS REST Services - Nettanlegg4 MapServer Layer 6
- **URL**: https://nve.geodataonline.no/arcgis/rest/services/Nettanlegg4/MapServer/6
- **Dataset**: Områdekonsesjonærer (Area Concession Holders)
- **Filter**: EIERTYPE='EVERK' (power utility companies)
- **Records Downloaded**: 88 grid company service areas
- **File Size**: 14 MB GeoJSON
- **Output**: `data/grid_companies/service_areas.geojson`

### 2. Loaded Service Areas to Database ✅
- **Script Created**: `scripts/09_load_grid_company_areas.sh`
- **Processing Steps**:
  1. Parse GeoJSON file with Python
  2. Extract geometry objects from Features
  3. Convert to PostGIS MultiPolygon geometries
  4. Generate SQL INSERT statements
  5. Load to temp table via docker exec
  6. Match to existing grid_companies by company_code (organization number)
  7. Clean up temp table
- **Records Loaded**: 88 service areas to temp table
- **Match Result**: **72 out of 84 companies matched** (85.7%)
- **Unmatched Companies**: 12 companies (mostly industrial/inactive)

### 3. Attempted Spatial Join ❌
- **Script Created**: `scripts/10_assign_grid_companies_to_cabins.sh`
- **Method**: PostGIS `ST_Within(cabin_point, service_area_polygon)`
- **Expected Result**: Assign grid company to each of 37,170 cabins
- **Actual Result**: **UPDATE 0 - ZERO cabins matched**
- **Investigation Triggered**: Why did no cabins match despite having 72 service areas?

---

## Critical Finding: Geographic Coverage Gap

### Cabin Distribution
- **Total Cabins**: 37,170
- **Geographic Extent**:
  - Longitude: 6.39 to 9.37
  - Latitude: 57.97 to 59.64
- **Region**: Agder fylke (southern Norway)

### Latitude Distribution of Cabins
| Latitude Band | Cabin Count | Percentage |
|--------------|-------------|------------|
| < 58.2 (far south) | 9,377 | 25.2% |
| 58.2-58.5 (south) | 7,752 | 20.9% |
| 58.5-58.8 (mid-south) | 10,047 | 27.0% |
| 58.8-59.0 (mid) | 5,305 | 14.3% |
| 59.0-59.3 (mid-north) | 1,815 | 4.9% |
| >= 59.3 (north) | 2,874 | 7.7% |

**Key Insight**: **73% of cabins (27,176)** are located south of latitude 58.8.

### Service Area Coverage
Service areas that intersect cabin bounding box:

| Company | Longitude | Latitude | Coverage |
|---------|-----------|----------|----------|
| ENIDA AS | 5.52-6.63 | 58.03-58.79 | Western Agder |
| LNETT AS | 4.96-6.94 | 58.61-59.37 | Western |
| FAGNE AS | 4.45-7.38 | 58.96-60.24 | Western/Northern |
| VESTMAR NETT AS | 9.16-9.97 | 58.60-59.00 | Eastern |
| LEDE AS | 9.23-10.68 | 58.72-59.70 | Eastern |
| **TELEMARK NETT AS** | 7.10-8.92 | **58.89**-59.98 | **Closest to cabin cluster** |
| DE NETT AS | 8.58-9.40 | 58.88-59.33 | Eastern |
| FØRE AS | 8.82-9.52 | 59.14-59.56 | Northern |
| EVERKET AS | 8.78-9.47 | 59.49-59.90 | Northern |
| RK NETT AS | 7.26-8.32 | 59.55-60.13 | Northern |

**Key Insight**: Most service areas start at latitude **58.88 or higher**, creating a gap of ~15-20 km from cabin locations.

### The Glitre Nett Mystery

Based on web research:
- **Glitre Nett** (formerly Agder Energi Nett) serves southern Agder region
- Company code: 982974011
- KILE cost: 98,580 NOK (#3 worst reliability in Norway)
- **Expected Service Area**: Lyngdal, Mandal, Farsund, Åseral municipalities

**NVE Data Reality**:
- Glitre Nett service_area_polygon IS in database
- **BUT polygon is in WRONG LOCATION**:
  - Longitude: 9.33 to 10.06 (near Oslo, eastern Norway)
  - Latitude: 59.41 to 59.78 (north of Oslo)
  - **95.5 km away from southern Agder cabins!**

This confirms **data quality issue** in NVE Nettanlegg4 dataset.

### Distance Analysis - Sample Cabin

**Test Cabin**: ID 2588 (Postal code 4865, lon 8.61, lat 58.74)

| Grid Company | Distance | Inside Polygon? |
|--------------|----------|----------------|
| TELEMARK NETT AS | 17.8 km | ❌ No |
| DE NETT AS | 30.2 km | ❌ No |
| VESTMAR NETT AS | 34.6 km | ❌ No |
| LEDE AS | 49.2 km | ❌ No |
| GLITRE NETT AS | 95.5 km | ❌ No |

**Closest service area is 17.8 km away** - cabin is NOT inside any polygon.

---

## Root Cause Analysis

### Why Spatial Join Failed

1. **Geographic Gap**: NVE service area polygons do not extend far enough south
2. **Missing Coverage**: No polygons cover latitude band 58.0-58.88 in central/eastern Agder
3. **Data Quality**: Glitre Nett polygon is in completely wrong location (near Oslo instead of southern Agder)
4. **Real-World vs Database**: Known service territories don't match NVE polygon geometries

### What We Know vs What NVE Data Shows

| Reality (from research) | NVE Database |
|------------------------|--------------|
| Glitre Nett serves Lyngdal, Mandal, Farsund | Polygon located near Oslo |
| Service area covers lat 58.0-58.7 | Polygon covers lat 59.4-59.8 |
| Central/coastal southern Agder | Eastern Norway region |

---

## Technical Details

### Query Used for Spatial Join
```sql
UPDATE cabins c
SET grid_company_code = gc.company_code
FROM grid_companies gc
WHERE gc.service_area_polygon IS NOT NULL
  AND ST_Within(c.geometry, gc.service_area_polygon);
```

**Result**: `UPDATE 0`

### Investigation Queries

**Check CRS compatibility:**
```sql
SELECT ST_SRID(geometry) FROM cabins LIMIT 1;  -- 4326 ✓
SELECT ST_SRID(service_area_polygon) FROM grid_companies
WHERE service_area_polygon IS NOT NULL LIMIT 1;  -- 4326 ✓
```

**Distance to nearest service area:**
```sql
WITH test_cabin AS (SELECT geometry FROM cabins WHERE id = 2588)
SELECT
    gc.company_name,
    ST_Distance(
        (SELECT geometry FROM test_cabin)::geography,
        gc.service_area_polygon::geography
    ) / 1000 as distance_km
FROM grid_companies gc
WHERE gc.service_area_polygon IS NOT NULL
ORDER BY distance_km LIMIT 5;
```

---

## Impact

### Blocked Functionality
- ❌ Cannot assign grid companies to cabins
- ❌ Cannot calculate cabin scores (requires KILE costs from grid company)
- ❌ Cannot generate postal code aggregations with quality metrics
- ❌ Core MVP functionality is blocked

### Affected Cabins
- **100% of cabins** (all 37,170) have no grid company assignment
- **73% of cabins** (27,176) are in the primary coverage gap (lat < 58.8)
- **27% of cabins** (9,994) might be assignable with nearest-neighbor approach

---

## Solution Options

### Option 1: Nearest-Neighbor Assignment (Fallback) ⚠️
**Approach**: Assign each cabin to closest grid company service area within reasonable distance threshold (e.g., 20-50 km)

**Pros**:
- Unblocks development immediately
- Simple to implement using ST_Distance
- Provides MVP functionality for testing

**Cons**:
- Not geographically accurate (cabins assigned to companies 20+ km away)
- May assign to wrong company in reality
- Not suitable for production/public use
- Won't reflect actual service territories

**Implementation**:
```sql
WITH cabin_assignments AS (
    SELECT DISTINCT ON (c.id)
        c.id,
        gc.company_code,
        ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000 as distance_km
    FROM cabins c
    CROSS JOIN grid_companies gc
    WHERE gc.service_area_polygon IS NOT NULL
    ORDER BY c.id, ST_Distance(c.geometry::geography, gc.service_area_polygon::geography)
)
UPDATE cabins c
SET grid_company_code = ca.company_code
FROM cabin_assignments ca
WHERE c.id = ca.id
  AND ca.distance_km < 50;  -- 50km threshold
```

### Option 2: Municipality-Based Assignment (Semi-Accurate) 🟡
**Approach**: Map municipalities to grid companies, assign cabins by their municipality

**Pros**:
- More accurate than pure distance-based
- Based on administrative boundaries (more stable)
- Can research/verify company-municipality relationships

**Cons**:
- Requires municipality boundaries data
- Some municipalities may have multiple grid companies
- Manual research required to build mapping table
- Still an approximation

**Implementation Steps**:
1. Load Norwegian municipality boundaries
2. Assign municipalities to cabins (spatial join)
3. Research which grid company serves each municipality
4. Create `municipality_grid_company` mapping table
5. Assign cabins based on municipality

### Option 3: Contact NVE for Corrected Data (Ideal) ✅
**Approach**: Report data quality issues to NVE and request corrected service area polygons

**Pros**:
- Official, authoritative data source
- Correct service territories
- Suitable for production use
- Helps improve public data quality

**Cons**:
- Unknown timeline for response/correction
- May not be a priority for NVE
- Requires bureaucratic communication
- Blocks development until resolved

**Contact**:
- NVE Geodata: https://www.nve.no/geodata-og-kart/
- Email: nve@nve.no
- Kartkatalog: https://kartkatalog.nve.no/

**Issues to Report**:
1. Glitre Nett AS (982974011) polygon in wrong location (near Oslo instead of southern Agder)
2. Missing coverage for lat 58.0-58.88 in Agder region
3. Request updated/corrected Nettanlegg4 dataset

### Option 4: Manual Polygon Creation (Labor-Intensive) 🔧
**Approach**: Manually create/correct service area polygons based on research and municipality boundaries

**Pros**:
- Full control over accuracy
- Can be done immediately
- Based on verified information

**Cons**:
- Very labor-intensive for all missing areas
- Requires domain knowledge of Norwegian grid operators
- Risk of legal/liability issues if used publicly
- Not official/authoritative

---

## Recommended Immediate Action

### Short-term (Today): Option 1 - Nearest-Neighbor
- Implement nearest-neighbor assignment with 50km threshold
- Allows development to continue
- Enables testing of scoring algorithm
- **Clearly mark data as "fallback/approximate"** in documentation

### Medium-term (This Week): Option 2 - Municipality Research
- Research Agder grid company service territories
- Build municipality → grid company mapping for southern Agder
- Refine cabin assignments using municipality boundaries
- Document sources and assumptions

### Long-term (Next Month): Option 3 - Official Data
- Contact NVE about data quality issues
- Request corrected service area polygons
- Switch to official data when available
- Validate against our research

---

## Files Created

- ✅ `data/grid_companies/service_areas.geojson` - Downloaded NVE service areas (14MB)
- ✅ `scripts/08_download_grid_company_areas.sh` - NVE download script
- ✅ `scripts/09_load_grid_company_areas.sh` - PostgreSQL loading script
- ✅ `scripts/10_assign_grid_companies_to_cabins.sh` - Spatial join script (failed due to gap)
- ✅ `claudedocs/DAY6_GRID_COVERAGE_GAP_ANALYSIS.md` - This document

---

## Database State

```sql
Grid Companies:           84 records ✅
Grid Companies with Areas: 72 records (85.7%) ✅
Cabins:                  37,170 records ✅
Cabins with Postal Codes: 37,170 (100%) ✅
Cabins with Grid Company:      0 (0%) ❌ BLOCKED

Service Area Coverage Gap: lat 58.0-58.88, lon 7-8 (southern Agder)
Affected Cabins: 27,176 (73%)
```

---

## Next Steps

**Decision Required**: Which solution option to pursue?

1. **Continue with fallback** (nearest-neighbor) to unblock development?
2. **Research municipalities** for semi-accurate mapping?
3. **Contact NVE** and wait for official correction?
4. **Combination approach**: Fallback now + official data later?

**Awaiting user guidance on how to proceed.**

---

**Last Updated**: 2025-11-22
