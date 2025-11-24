#!/bin/bash
# Fast assignment using planar geometry (geometry type, not geography)
# Much faster for small regions like Agder

echo "=========================================="
echo "Fast Planar Geometry Assignment"
echo "=========================================="
echo ""
echo "⚠️  Using planar geometry for speed"
echo "   (Accurate enough for Agder region)"
echo ""

# Check current state
echo "1. Current database state:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM cabins) as total_cabins,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NOT NULL) as companies_with_areas,
    (SELECT COUNT(*) FROM cabins WHERE grid_company_code IS NOT NULL) as cabins_with_company;
"

# Use planar geometry (geometry type) for much faster calculations
echo ""
echo "2. Assigning using planar geometry (fast!)..."

docker exec svakenett-postgis psql -U postgres -d svakenett -c "
-- Create temp table with nearest assignments using PLANAR distance
DROP TABLE IF EXISTS temp_nearest_assignments;
CREATE TEMP TABLE temp_nearest_assignments AS
SELECT DISTINCT ON (c.id)
    c.id as cabin_id,
    gc.company_code,
    ST_Distance(c.geometry, gc.service_area_polygon) as distance_degrees
FROM cabins c
JOIN grid_companies gc
    ON ST_DWithin(c.geometry, gc.service_area_polygon, 1.0)  -- ~100km in degrees at this latitude
WHERE gc.service_area_polygon IS NOT NULL
ORDER BY c.id, ST_Distance(c.geometry, gc.service_area_polygon);

-- Show temp table stats
SELECT COUNT(*) as assignments_found FROM temp_nearest_assignments;

-- Update cabins from temp table
UPDATE cabins c
SET grid_company_code = ta.company_code
FROM temp_nearest_assignments ta
WHERE c.id = ta.cabin_id;

-- Verify results
SELECT
    COUNT(*) as total_cabins,
    COUNT(grid_company_code) as cabins_with_company,
    COUNT(*) - COUNT(grid_company_code) as cabins_without_company,
    ROUND(100.0 * COUNT(grid_company_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

# Show top companies
echo ""
echo "3. Top grid companies by cabin count:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    gc.company_name,
    gc.company_code,
    COUNT(c.id) as cabin_count,
    gc.kile_cost_nok
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
GROUP BY gc.company_name, gc.company_code, gc.kile_cost_nok
ORDER BY COUNT(c.id) DESC
LIMIT 10;
"

# KILE statistics
echo ""
echo "4. KILE statistics:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(DISTINCT gc.company_code) as companies_serving_cabins,
    ROUND(AVG(gc.kile_cost_nok)::numeric, 0) as avg_kile_cost,
    MAX(gc.kile_cost_nok) as max_kile_cost,
    MIN(gc.kile_cost_nok) as min_kile_cost
FROM grid_companies gc
WHERE gc.company_code IN (
    SELECT DISTINCT grid_company_code
    FROM cabins
    WHERE grid_company_code IS NOT NULL
);
"

echo ""
echo "=========================================="
echo "[OK] Fast planar assignment complete!"
echo "=========================================="
