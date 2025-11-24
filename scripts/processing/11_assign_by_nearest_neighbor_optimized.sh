#!/bin/bash
# Optimized: Assign grid companies using spatial index and batched approach
# Uses ST_DWithin for spatial filtering before distance calculation

echo "=========================================="
echo "Optimized Nearest-Neighbor Assignment"
echo "=========================================="
echo ""
echo "⚠️  WARNING: Fallback approach due to NVE data gaps"
echo ""

# Check current state
echo "1. Current database state:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM cabins) as total_cabins,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NOT NULL) as companies_with_areas,
    (SELECT COUNT(*) FROM cabins WHERE grid_company_code IS NOT NULL) as cabins_with_company;
"

# Optimized approach: Use ST_DWithin with index, then calculate exact distances
echo ""
echo "2. Assigning cabins using spatial index..."
echo "   Using 100km search radius with ST_DWithin for efficiency"

docker exec svakenett-postgis psql -U postgres -d svakenett -c "
-- Create temp table for nearest assignments using spatial index
CREATE TEMP TABLE temp_nearest_assignments AS
SELECT DISTINCT ON (c.id)
    c.id as cabin_id,
    gc.company_code,
    ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000 as distance_km
FROM cabins c
JOIN grid_companies gc
    ON ST_DWithin(c.geometry::geography, gc.service_area_polygon::geography, 100000)  -- 100km radius
WHERE gc.service_area_polygon IS NOT NULL
ORDER BY c.id, ST_Distance(c.geometry::geography, gc.service_area_polygon::geography);

-- Update cabins from temp table
UPDATE cabins c
SET grid_company_code = ta.company_code
FROM temp_nearest_assignments ta
WHERE c.id = ta.cabin_id
  AND ta.distance_km < 50;  -- 50km threshold

-- Verify results
SELECT
    COUNT(*) as total_cabins,
    COUNT(grid_company_code) as cabins_with_company,
    COUNT(*) - COUNT(grid_company_code) as cabins_without_company,
    ROUND(100.0 * COUNT(grid_company_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

# Show statistics
echo ""
echo "3. Distance statistics:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
WITH distances AS (
    SELECT
        c.id,
        ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000 as distance_km
    FROM cabins c
    JOIN grid_companies gc ON c.grid_company_code = gc.company_code
    WHERE c.grid_company_code IS NOT NULL
      AND gc.service_area_polygon IS NOT NULL
)
SELECT
    COUNT(*) as assigned_cabins,
    ROUND(MIN(distance_km)::numeric, 1) as min_km,
    ROUND(AVG(distance_km)::numeric, 1) as avg_km,
    ROUND(MAX(distance_km)::numeric, 1) as max_km,
    COUNT(*) FILTER (WHERE distance_km < 10) as within_10km,
    COUNT(*) FILTER (WHERE distance_km BETWEEN 10 AND 20) as range_10_20km,
    COUNT(*) FILTER (WHERE distance_km BETWEEN 20 AND 50) as range_20_50km
FROM distances;
"

# Top companies
echo ""
echo "4. Top grid companies by cabin count:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    gc.company_name,
    gc.company_code,
    COUNT(c.id) as cabin_count,
    gc.kile_cost_nok,
    ROUND(AVG(ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000)::numeric, 1) as avg_dist_km
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE gc.service_area_polygon IS NOT NULL
GROUP BY gc.company_name, gc.company_code, gc.kile_cost_nok
ORDER BY COUNT(c.id) DESC
LIMIT 10;
"

echo ""
echo "=========================================="
echo "[OK] Optimized assignment complete!"
echo "=========================================="
