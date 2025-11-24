-- ============================================================================
-- Validate NVE Infrastructure Data Load
-- ============================================================================
-- Purpose: Comprehensive validation of loaded NVE grid infrastructure data
-- Checks: Record counts, CRS, spatial indexes, data quality, grid linkage
-- Author: Klaus
-- Date: 2025-01-22
-- ============================================================================

\echo '========================================'
\echo 'NVE Infrastructure Data Validation'
\echo '========================================'

-- ============================================================================
-- CHECK 1: Data Volume Validation
-- ============================================================================

\echo ''
\echo '[1/7] Data Volume Check'
\echo ''

SELECT
    'Power Lines' as table_name,
    COUNT(*) as records,
    CASE
        WHEN COUNT(*) >= 9000 AND COUNT(*) <= 11000 THEN '✓ Expected'
        ELSE '⚠ Unexpected'
    END as status
FROM nve_power_lines

UNION ALL

SELECT
    'Power Poles',
    COUNT(*),
    CASE
        WHEN COUNT(*) >= 60000 AND COUNT(*) <= 65000 THEN '✓ Expected'
        ELSE '⚠ Unexpected'
    END
FROM nve_power_poles

UNION ALL

SELECT
    'Transformers',
    COUNT(*),
    CASE
        WHEN COUNT(*) >= 100 AND COUNT(*) <= 150 THEN '✓ Expected'
        ELSE '⚠ Unexpected'
    END
FROM nve_transformers;

-- ============================================================================
-- CHECK 2: CRS Validation
-- ============================================================================

\echo ''
\echo '[2/7] Coordinate Reference System Check'
\echo ''

SELECT
    'Power Lines CRS' as check_name,
    ST_SRID(geometry) as srid,
    COUNT(*) as records,
    CASE
        WHEN ST_SRID(geometry) = 4326 THEN '✓ WGS84'
        ELSE '❌ Wrong CRS'
    END as status
FROM nve_power_lines
GROUP BY ST_SRID(geometry)

UNION ALL

SELECT
    'Power Poles CRS',
    ST_SRID(geometry),
    COUNT(*),
    CASE
        WHEN ST_SRID(geometry) = 4326 THEN '✓ WGS84'
        ELSE '❌ Wrong CRS'
    END
FROM nve_power_poles
GROUP BY ST_SRID(geometry)

UNION ALL

SELECT
    'Transformers CRS',
    ST_SRID(geometry),
    COUNT(*),
    CASE
        WHEN ST_SRID(geometry) = 4326 THEN '✓ WGS84'
        ELSE '❌ Wrong CRS'
    END
FROM nve_transformers
GROUP BY ST_SRID(geometry);

-- ============================================================================
-- CHECK 3: Spatial Index Verification
-- ============================================================================

\echo ''
\echo '[3/7] Spatial Index Verification'
\echo ''

SELECT
    tablename,
    indexname,
    CASE
        WHEN indexdef LIKE '%USING gist%' THEN '✓ GIST Index'
        ELSE '❌ No GIST Index'
    END as status
FROM pg_indexes
WHERE tablename IN ('nve_power_lines', 'nve_power_poles', 'nve_transformers')
  AND indexname LIKE '%geom%'
ORDER BY tablename;

-- ============================================================================
-- CHECK 4: 22kV Distribution Grid Filter
-- ============================================================================

\echo ''
\echo '[4/7] 22kV Distribution Grid Analysis'
\echo ''

SELECT
    'Distribution Lines (Level 3)' as category,
    COUNT(*) as line_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM nve_power_lines), 1) as percentage,
    ROUND(AVG(alder_aar), 1) as avg_age_years,
    MIN(driftsatt_aar) as oldest_year,
    MAX(driftsatt_aar) as newest_year
FROM nve_power_lines
WHERE nve_nett_nivaa = 3

UNION ALL

SELECT
    '22kV Voltage Lines',
    COUNT(*),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM nve_power_lines), 1),
    ROUND(AVG(alder_aar), 1),
    MIN(driftsatt_aar),
    MAX(driftsatt_aar)
FROM nve_power_lines
WHERE spenning_kv = 22.0

UNION ALL

SELECT
    'Target: Level 3 + 22kV',
    COUNT(*),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM nve_power_lines), 1),
    ROUND(AVG(alder_aar), 1),
    MIN(driftsatt_aar),
    MAX(driftsatt_aar)
FROM nve_power_lines
WHERE nve_nett_nivaa = 3 AND spenning_kv = 22.0;

-- ============================================================================
-- CHECK 5: Grid Company Linkage Verification
-- ============================================================================

\echo ''
\echo '[5/7] Grid Company Linkage Check'
\echo ''

SELECT
    pl.eier,
    pl.eier_org_nr,
    gc.company_name,
    gc.kile_cost_nok,
    COUNT(*) as lines_owned,
    CASE
        WHEN gc.company_code IS NOT NULL THEN '✓ Linked'
        ELSE '⚠ No KILE Data'
    END as kile_status
FROM nve_power_lines pl
LEFT JOIN grid_companies gc ON pl.eier_org_nr::text = gc.company_code
WHERE pl.nve_nett_nivaa = 3
GROUP BY pl.eier, pl.eier_org_nr, gc.company_name, gc.kile_cost_nok, gc.company_code
ORDER BY lines_owned DESC
LIMIT 5;

-- ============================================================================
-- CHECK 6: Geographic Coverage Check
-- ============================================================================

\echo ''
\echo '[6/7] Geographic Coverage (Bounding Box)'
\echo ''

SELECT
    'Power Lines Extent' as layer,
    ROUND(ST_XMin(ST_Extent(geometry))::numeric, 4) as min_lon,
    ROUND(ST_YMin(ST_Extent(geometry))::numeric, 4) as min_lat,
    ROUND(ST_XMax(ST_Extent(geometry))::numeric, 4) as max_lon,
    ROUND(ST_YMax(ST_Extent(geometry))::numeric, 4) as max_lat,
    CASE
        WHEN ST_XMin(ST_Extent(geometry)) >= 6.0 AND ST_XMax(ST_Extent(geometry)) <= 9.5
         AND ST_YMin(ST_Extent(geometry)) >= 58.0 AND ST_YMax(ST_Extent(geometry)) <= 59.5
        THEN '✓ Agder Region'
        ELSE '⚠ Check Coverage'
    END as coverage_status
FROM nve_power_lines

UNION ALL

SELECT
    'Power Poles Extent',
    ROUND(ST_XMin(ST_Extent(geometry))::numeric, 4),
    ROUND(ST_YMin(ST_Extent(geometry))::numeric, 4),
    ROUND(ST_XMax(ST_Extent(geometry))::numeric, 4),
    ROUND(ST_YMax(ST_Extent(geometry))::numeric, 4),
    CASE
        WHEN ST_XMin(ST_Extent(geometry)) >= 6.0 AND ST_XMax(ST_Extent(geometry)) <= 9.5
         AND ST_YMin(ST_Extent(geometry)) >= 58.0 AND ST_YMax(ST_Extent(geometry)) <= 59.5
        THEN '✓ Agder Region'
        ELSE '⚠ Check Coverage'
    END
FROM nve_power_poles;

-- ============================================================================
-- CHECK 7: Sample Spatial Query Performance
-- ============================================================================

\echo ''
\echo '[7/7] Spatial Query Performance Test'
\echo ''

-- Test: Find nearest power line to a sample point (should be fast with GIST index)
EXPLAIN ANALYZE
SELECT
    id,
    objekt_type,
    spenning_kv,
    ST_Distance(
        geometry::geography,
        ST_SetSRID(ST_MakePoint(7.5, 58.5), 4326)::geography
    ) / 1000.0 as distance_km
FROM nve_power_lines
WHERE nve_nett_nivaa = 3
ORDER BY geometry <-> ST_SetSRID(ST_MakePoint(7.5, 58.5), 4326)
LIMIT 1;

-- ============================================================================
-- DATA QUALITY SUMMARY
-- ============================================================================

\echo ''
\echo '========================================'
\echo 'Data Quality Summary'
\echo '========================================'
\echo ''

-- Null value check
SELECT
    'Null Values in Power Lines' as check_name,
    SUM(CASE WHEN spenning_kv IS NULL THEN 1 ELSE 0 END) as null_voltage,
    SUM(CASE WHEN eier_org_nr IS NULL THEN 1 ELSE 0 END) as null_owner,
    SUM(CASE WHEN driftsatt_aar IS NULL THEN 1 ELSE 0 END) as null_year,
    CASE
        WHEN SUM(CASE WHEN spenning_kv IS NULL THEN 1 ELSE 0 END) < 100 THEN '✓ Good'
        ELSE '⚠ Many Nulls'
    END as status
FROM nve_power_lines;

-- Geometry validity check
\echo ''
\echo '[Geometry Validity Check]'
\echo ''

SELECT
    'Power Lines Geometry' as layer,
    COUNT(*) as total_features,
    SUM(CASE WHEN ST_IsValid(geometry) THEN 1 ELSE 0 END) as valid_geoms,
    SUM(CASE WHEN NOT ST_IsValid(geometry) THEN 1 ELSE 0 END) as invalid_geoms,
    CASE
        WHEN SUM(CASE WHEN NOT ST_IsValid(geometry) THEN 1 ELSE 0 END) = 0 THEN '✓ All Valid'
        ELSE '⚠ Has Invalid Geometries'
    END as status
FROM nve_power_lines

UNION ALL

SELECT
    'Power Poles Geometry',
    COUNT(*),
    SUM(CASE WHEN ST_IsValid(geometry) THEN 1 ELSE 0 END),
    SUM(CASE WHEN NOT ST_IsValid(geometry) THEN 1 ELSE 0 END),
    CASE
        WHEN SUM(CASE WHEN NOT ST_IsValid(geometry) THEN 1 ELSE 0 END) = 0 THEN '✓ All Valid'
        ELSE '⚠ Has Invalid Geometries'
    END
FROM nve_power_poles;

-- ============================================================================
-- FINAL VALIDATION STATUS
-- ============================================================================

\echo ''
\echo '========================================'
\echo '✓ Validation Complete'
\echo '========================================'
\echo ''

SELECT
    'Validation Status' as metric,
    CASE
        WHEN (SELECT COUNT(*) FROM nve_power_lines) >= 9000
         AND (SELECT COUNT(*) FROM nve_power_poles) >= 60000
         AND (SELECT COUNT(*) FROM nve_transformers) >= 100
         AND (SELECT COUNT(*) FILTER (WHERE ST_SRID(geometry) = 4326) FROM nve_power_lines) = (SELECT COUNT(*) FROM nve_power_lines)
        THEN '✅ PASS - Data loaded successfully'
        ELSE '❌ FAIL - Data issues detected'
    END as status;

\echo ''
\echo 'Next steps:'
\echo '  1. Calculate cabin distances: psql $DATABASE_URL -f scripts/calculate_cabin_grid_distances.sql'
\echo '  2. Calculate weak grid scores: psql $DATABASE_URL -f scripts/calculate_weak_grid_scores.sql'
\echo ''
