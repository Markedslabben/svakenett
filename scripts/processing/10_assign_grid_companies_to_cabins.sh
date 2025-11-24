#!/bin/bash
# Assign grid companies to cabins via spatial join

echo "=========================================="
echo "Assigning Grid Companies to Cabins"
echo "=========================================="

# Check current state
echo ""
echo "1. Current database state:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM cabins) as total_cabins,
    (SELECT COUNT(*) FROM grid_companies) as total_grid_companies,
    (SELECT COUNT(*) FROM grid_companies WHERE service_area_polygon IS NOT NULL) as companies_with_areas,
    (SELECT COUNT(*) FROM cabins WHERE grid_company_code IS NOT NULL) as cabins_with_company;
"

# Perform spatial join using ST_Within
echo ""
echo "2. Performing spatial join (this may take 1-2 minutes)..."
echo "   Matching cabin locations to grid company service areas..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
UPDATE cabins c
SET grid_company_code = gc.company_code
FROM grid_companies gc
WHERE gc.service_area_polygon IS NOT NULL
  AND ST_Within(c.geometry, gc.service_area_polygon);
"

# Verify results
echo ""
echo "3. Verification after spatial join:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(*) as total_cabins,
    COUNT(grid_company_code) as cabins_with_company,
    COUNT(*) - COUNT(grid_company_code) as cabins_without_company,
    ROUND(100.0 * COUNT(grid_company_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

# Show top grid companies by cabin count
echo ""
echo "4. Top 10 grid companies by cabin count:"
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

# Show KILE statistics for companies serving cabins
echo ""
echo "5. KILE statistics for companies serving our cabins:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(DISTINCT gc.company_code) as companies_serving_cabins,
    SUM(gc.kile_cost_nok) as total_kile_costs,
    AVG(gc.kile_cost_nok) as avg_kile_cost,
    MAX(gc.kile_cost_nok) as max_kile_cost
FROM grid_companies gc
WHERE gc.company_code IN (SELECT DISTINCT grid_company_code FROM cabins WHERE grid_company_code IS NOT NULL);
"

# Sample cabins with grid company assignments
echo ""
echo "6. Sample cabins with grid company assignments:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    c.id,
    c.postal_code,
    gc.company_name,
    gc.kile_cost_nok,
    ST_X(c.geometry) as lon,
    ST_Y(c.geometry) as lat
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE gc.kile_cost_nok > 1000
LIMIT 5;
"

echo ""
echo "=========================================="
echo "[OK] Grid company assignment complete!"
echo "=========================================="
