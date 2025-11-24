#!/bin/bash
# Fallback: Assign grid companies to cabins using nearest-neighbor approach
# WARNING: This is an approximation due to NVE service area coverage gaps

echo "=========================================="
echo "Nearest-Neighbor Grid Company Assignment"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This is a FALLBACK approach due to NVE data gaps"
echo "   Cabins will be assigned to the CLOSEST grid company service area"
echo "   This may not reflect actual service territories"
echo "   See claudedocs/DAY6_GRID_COVERAGE_GAP_ANALYSIS.md for details"
echo ""

# Check current state
echo "1. Current database state:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM cabins) as total_cabins,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NOT NULL) as companies_with_areas,
    (SELECT COUNT(*) FROM cabins WHERE grid_company_code IS NOT NULL) as cabins_with_company;
"

# Perform nearest-neighbor assignment with distance threshold
echo ""
echo "2. Assigning cabins to nearest grid company (max 50km distance)..."
echo "   This may take 2-3 minutes for 37,170 cabins..."

docker exec svakenett-postgis psql -U postgres -d svakenett -c "
WITH cabin_assignments AS (
    SELECT DISTINCT ON (c.id)
        c.id,
        gc.company_code,
        gc.company_name,
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
"

# Verify results
echo ""
echo "3. Verification after nearest-neighbor assignment:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(*) as total_cabins,
    COUNT(grid_company_code) as cabins_with_company,
    COUNT(*) - COUNT(grid_company_code) as cabins_without_company,
    ROUND(100.0 * COUNT(grid_company_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

# Show distance statistics
echo ""
echo "4. Distance statistics (cabin to assigned grid company):"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
WITH distances AS (
    SELECT
        c.id,
        c.grid_company_code,
        ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000 as distance_km
    FROM cabins c
    JOIN grid_companies gc ON c.grid_company_code = gc.company_code
    WHERE c.grid_company_code IS NOT NULL
      AND gc.service_area_polygon IS NOT NULL
)
SELECT
    COUNT(*) as assigned_cabins,
    ROUND(MIN(distance_km)::numeric, 1) as min_distance_km,
    ROUND(AVG(distance_km)::numeric, 1) as avg_distance_km,
    ROUND(MAX(distance_km)::numeric, 1) as max_distance_km,
    COUNT(*) FILTER (WHERE distance_km < 10) as within_10km,
    COUNT(*) FILTER (WHERE distance_km BETWEEN 10 AND 20) as between_10_20km,
    COUNT(*) FILTER (WHERE distance_km BETWEEN 20 AND 50) as between_20_50km
FROM distances;
"

# Show top grid companies by cabin count
echo ""
echo "5. Top 10 grid companies by assigned cabin count:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    gc.company_name,
    gc.company_code,
    COUNT(c.id) as cabin_count,
    gc.kile_cost_nok,
    ROUND(AVG(ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000)::numeric, 1) as avg_distance_km
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE gc.service_area_polygon IS NOT NULL
GROUP BY gc.company_name, gc.company_code, gc.kile_cost_nok
ORDER BY COUNT(c.id) DESC
LIMIT 10;
"

# Show KILE statistics for companies serving cabins
echo ""
echo "6. KILE statistics for companies serving our cabins:"
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

# Sample cabins with assignments
echo ""
echo "7. Sample cabins with grid company assignments:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    c.id,
    c.postal_code,
    gc.company_name,
    gc.kile_cost_nok,
    ROUND(ST_Distance(c.geometry::geography, gc.service_area_polygon::geography) / 1000::numeric, 1) as distance_km,
    ROUND(ST_X(c.geometry)::numeric, 2) as lon,
    ROUND(ST_Y(c.geometry)::numeric, 2) as lat
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE gc.service_area_polygon IS NOT NULL
ORDER BY RANDOM()
LIMIT 5;
"

echo ""
echo "=========================================="
echo "⚠️  IMPORTANT NOTES"
echo "=========================================="
echo "This assignment uses NEAREST grid company service area"
echo "Due to NVE data gaps, assigned companies may not be the ACTUAL provider"
echo ""
echo "Known issues:"
echo "- 73% of cabins are 17-50km from nearest service area"
echo "- Glitre Nett (should serve southern Agder) has wrong polygon location"
echo "- Service areas missing for lat 58.0-58.88 region"
echo ""
echo "See claudedocs/DAY6_GRID_COVERAGE_GAP_ANALYSIS.md for full details"
echo ""
echo "[OK] Nearest-neighbor assignment complete!"
echo "=========================================="
