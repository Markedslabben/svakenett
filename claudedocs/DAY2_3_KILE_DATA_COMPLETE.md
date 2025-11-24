# Day 2-3 Complete: KILE Statistics Integration

**Date**: 2025-11-22
**Status**: ✅ Grid company KILE data loaded successfully!

---

## Summary

Successfully integrated Norwegian grid company reliability data (KILE statistics) from NVE into the svakenett database.

**Result:** 84 grid companies with 2023 KILE cost data available for scoring calculations.

---

## What Was Accomplished

### 1. Data Acquisition ✅
- **Source**: NVE (Norges vassdrags- og energidirektorat)
- **Files Downloaded**:
  - `grunnlagsdata_ir_2024.xlsx` (179 KB) - 2024 foundation data
  - `grunnlagsdata_ir_2025.xlsx` (175 KB) - 2025 foundation data
- **Data Format**: Excel workbooks from eRapp and TEK systems
- **URL**: https://www.nve.no/media/17633/grunnlagsdata_ir_2025.xlsx

### 2. Data Processing ✅
- **Script Created**: `scripts/03_process_kile_data.py`
- **Processing Steps**:
  1. Read Excel file (441 total rows across all years)
  2. Filter for most recent year (2023) → 88 companies
  3. Convert KILE columns to numeric (Dnett, Rnett, Tnett)
  4. Calculate total KILE per company
  5. Filter companies with >0 customers → 84 companies
  6. Calculate KILE per customer metric
  7. Export to CSV: `data/kile/grid_companies_kile.csv`

### 3. Database Loading ✅
- **Script Created**: `scripts/04_load_kile_to_db.sh`
- **Loaded Into**: `grid_companies` table
- **Columns Populated**:
  - `company_code` - Organization number (PRIMARY KEY)
  - `company_name` - Grid company name
  - `kile_cost_nok` - Total KILE penalty costs (NOK)
  - `data_year` - 2023
- **Records Loaded**: 84 grid companies

---

## KILE Data Explanation

### What is KILE?

**KILE** = Kvalitetsjusterte Inntektsrammer ved ikke-levert Energi
(Quality-adjusted revenue caps for non-delivered energy)

- **Financial penalty** imposed by NVE on grid companies for poor reliability
- Higher KILE costs = Worse grid reliability
- Accounts for both interruption **frequency** and **duration**
- More direct measure than SAIDI/SAIFI for our use case

### Why KILE is Perfect for This Project

**Traditional metrics (SAIDI/SAIFI):**
- SAIDI = System Average Interruption Duration Index (hours)
- SAIFI = System Average Interruption Frequency Index (count)
- Useful for comparison but not financially motivated

**KILE advantages:**
- ✅ Direct financial consequence of poor reliability
- ✅ Combines duration and frequency into single metric
- ✅ Officially regulated by NVE
- ✅ Higher costs = stronger business case for off-grid solutions
- ✅ Publicly available and audited

---

## Data Verification

### Database State
```sql
Grid Companies: 84 records
Cabins:         37,170 records
```

### Top 5 Worst Reliability (2023)

| Rank | Company | KILE Cost (NOK) |
|------|---------|-----------------|
| 1 | ELVIA AS | 168,943 |
| 2 | SVABO INDUSTRINETT AS | 118,682 |
| 3 | GLITRE NETT AS | 98,580 |
| 4 | LEDE AS | 46,446 |
| 5 | TENSIO TS AS | 45,432 |

**Total KILE costs (all 84 companies):** 888,013 NOK

### Best Reliability (2023)

Companies with **0 KILE costs** (perfect reliability):
- TINFOS AS
- KE NETT AS
- VANG ENERGIVERK AS
- RK NETT AS
- STRAUMNETT AS

---

## Technical Details

### Data Sources

**Primary Source:**
- NVE eRapp and TEK systems
- Published annually as "Grunnlagsdata.xlsx"
- URL: https://www.nve.no/reguleringsmyndigheten/bransje/bransjeoppgaver/inntektsrammer/

**Data Year:** 2023 (most recent complete year)

**Coverage:** National - all grid companies in Norway

### File Structure

**Excel File Contents:**
- 441 rows total (all companies, multiple years)
- 69 columns (economic and technical data)
- Key columns:
  - Organisasjonsnummer (org number)
  - Selskapsnavn (company name)
  - Årstall (year)
  - KILE Dnett (distribution network)
  - KILE Rnett (regional network)
  - KILE Tnett (transmission network)
  - Antall abonnementer (number of customers)

**Processed CSV:**
- 84 rows (2023 data only)
- 9 columns:
  - org_number
  - company_name
  - year
  - kile_dnett, kile_rnett, kile_tnett
  - kile_total
  - num_customers
  - kile_per_customer

### Database Schema

```sql
CREATE TABLE grid_companies (
    id SERIAL PRIMARY KEY,
    company_name VARCHAR(200) NOT NULL,
    company_code VARCHAR(50) UNIQUE,  -- org number
    saidi_hours REAL,                  -- Not populated yet
    saifi_count REAL,                  -- Not populated yet
    kile_cost_nok REAL,               -- ✓ Populated from NVE data
    service_area_polygon GEOMETRY(MultiPolygon, 4326),  -- Not populated yet
    data_year INTEGER NOT NULL,        -- ✓ 2023
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## Challenges and Solutions

### Challenge 1: Finding SAIDI/SAIFI Data
- **Issue**: NVE interruption statistics in interactive dashboards, no direct download
- **Solution**: Used KILE cost data instead (superior metric for our use case)
- **Outcome**: Better data quality than originally planned

### Challenge 2: Excel Data Format
- **Issue**: First row contains metadata labels, not data
- **Solution**: Filter out rows where year='y', convert to numeric
- **Outcome**: Clean data processing

### Challenge 3: Database Schema Mismatch
- **Issue**: CSV had extra columns (num_customers, kile_per_customer)
- **Solution**: Map only to existing schema columns
- **Outcome**: Successful load with 84 companies

### Challenge 4: Missing Python Packages
- **Issue**: SQLAlchemy not available in Anaconda environment
- **Solution**: Used bash script to generate SQL INSERT statements
- **Outcome**: Reliable data loading without additional dependencies

---

## Next Steps (Day 4-7)

### CRITICAL: Grid Company Service Areas

**Problem:** We need to match each cabin to its grid company to assign KILE scores.

**Current Gap:** We have:
- ✅ 37,170 cabin locations (Point geometries)
- ✅ 84 grid companies with KILE costs
- ❌ Grid company service area boundaries (MultiPolygon geometries)

**Solution Options:**

1. **Find Official Service Area Data**
   - Source: NVE, DSB, or grid companies directly
   - Format: Shapefile, GeoJSON, or PostGIS dump
   - Ideal: Complete coverage of Norway

2. **Alternative: Municipality-Based Assignment**
   - Assumption: Each municipality served by 1-2 primary grid companies
   - Source: Manual mapping or grid company websites
   - Less accurate but workable for MVP

3. **Alternative: Postal Code Assignment**
   - Similar to municipality approach
   - Requires postal code boundaries (Day 4-5 task)
   - Can combine with municipality data

**Recommended Approach for MVP:**
- Use municipality-based assignment as interim solution
- Create manual mapping table: municipality → grid_company_code
- Update as official service area data becomes available

### Day 4-5: Postal Code Boundaries
1. Download postal code boundaries from Geonorge/SSB
2. Load into `postal_codes` table
3. Spatial join: Assign postal codes to cabins
4. Update `cabins.postal_code` column

### Day 6-7: Geographic Enrichment
1. Calculate distance to nearest town (proxy for grid quality)
2. Add terrain data (optional): elevation, slope
3. Update cabin geographic attributes

---

## Files Created

- ✅ `data/kile/grunnlagsdata_ir_2024.xlsx` - NVE foundation data 2024
- ✅ `data/kile/grunnlagsdata_ir_2025.xlsx` - NVE foundation data 2025
- ✅ `data/kile/grid_companies_kile.csv` - Processed KILE data
- ✅ `scripts/03_process_kile_data.py` - Excel to CSV processor
- ✅ `scripts/04_load_kile_to_db.sh` - CSV to PostgreSQL loader
- ✅ `scripts/inspect_kile_data.py` - Data inspection utility
- ✅ `claudedocs/DAY2_3_KILE_DATA_COMPLETE.md` - This document

---

## Key Learnings

### 1. KILE is Better Than SAIDI/SAIFI
- Financial metric with direct business implications
- Combined measure of reliability (duration × frequency)
- Easier to obtain from public sources

### 2. NVE Data Quality
- Comprehensive coverage (all grid companies in Norway)
- Audited and regulated data
- Consistent annual publication

### 3. Service Area Data Gap
- Most critical missing piece for cabin→company matching
- Not readily available in public datasets
- Will require creative solution or additional data acquisition

### 4. Excel Data Handling
- Always check for metadata rows in government datasets
- Use numeric conversion with error handling
- Validate data types before calculations

---

## Statistics

| Metric | Value |
|--------|-------|
| Grid companies loaded | 84 |
| Data year | 2023 |
| Total KILE costs | 888,013 NOK |
| Average KILE/customer | 11.52 NOK |
| Highest KILE cost | 168,943 NOK (ELVIA AS) |
| Companies with 0 KILE | 5 |
| Processing time | ~5 minutes |

---

## Success Criteria

- ✅ Download NVE KILE data
- ✅ Process and clean data
- ✅ Load 80+ grid companies
- ✅ Verify data integrity
- ✅ Document methodology
- ⏳ Match cabins to grid companies (blocked on service area data)

**Status:** Day 2-3 objectives complete, pending service area data for cabin matching.

---

**Last Updated**: 2025-11-22 03:00 UTC
