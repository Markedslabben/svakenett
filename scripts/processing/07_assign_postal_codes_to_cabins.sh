#!/bin/bash
# Perform spatial join to assign postal codes to cabins

echo "=========================================="
echo "Assigning Postal Codes to Cabins"
echo "=========================================="

# Check current state
echo ""
echo "1. Current database state:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    (SELECT COUNT(*) FROM cabins) as total_cabins,
    (SELECT COUNT(*) FROM postal_codes) as total_postal_codes,
    (SELECT COUNT(*) FROM cabins WHERE postal_code IS NOT NULL) as cabins_with_postal_code;
"

# Perform spatial join using ST_Within
echo ""
echo "2. Performing spatial join (this may take 1-2 minutes)..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
UPDATE cabins c
SET postal_code = pc.postal_code
FROM postal_codes pc
WHERE ST_Within(c.geometry, pc.geometry);
"

# Verify results
echo ""
echo "3. Verification after spatial join:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(*) as total_cabins,
    COUNT(postal_code) as cabins_with_postal_code,
    COUNT(*) - COUNT(postal_code) as cabins_without_postal_code,
    ROUND(100.0 * COUNT(postal_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

# Show breakdown by postal code prefix (county)
echo ""
echo "4. Coverage by region:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    SUBSTRING(postal_code FROM 1 FOR 1) as region_prefix,
    COUNT(*) as cabin_count
FROM cabins
WHERE postal_code IS NOT NULL
GROUP BY SUBSTRING(postal_code FROM 1 FOR 1)
ORDER BY region_prefix;
"

# Show Agder region (4xxx) coverage
echo ""
echo "5. Agder region (postal codes 4xxx) coverage:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(*) as agder_cabins,
    COUNT(DISTINCT postal_code) as unique_postal_codes
FROM cabins
WHERE postal_code LIKE '4%';
"

# Sample cabins with postal codes
echo ""
echo "6. Sample cabins with assigned postal codes:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    c.id,
    c.building_type,
    c.postal_code,
    pc.postal_name,
    ST_X(c.geometry) as lon,
    ST_Y(c.geometry) as lat
FROM cabins c
LEFT JOIN postal_codes pc ON c.postal_code = pc.postal_code
WHERE c.postal_code IS NOT NULL
LIMIT 5;
"

echo ""
echo "=========================================="
echo "[OK] Postal code assignment complete!"
echo "=========================================="
