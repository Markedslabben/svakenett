#!/bin/bash
# Batch processing: Assign grid companies in chunks of 1000 cabins
# Much faster than processing all 37K at once

echo "=========================================="
echo "Batch Processing Grid Company Assignment"
echo "=========================================="
echo ""

# Get total cabin count
TOTAL=$(docker exec svakenett-postgis psql -U postgres -d svakenett -t -c "SELECT COUNT(*) FROM cabins;")
BATCH_SIZE=1000
BATCHES=$(( ($TOTAL + $BATCH_SIZE - 1) / $BATCH_SIZE ))

echo "Total cabins: $TOTAL"
echo "Batch size: $BATCH_SIZE"
echo "Total batches: $BATCHES"
echo ""

# Process in batches
for i in $(seq 0 $(($BATCHES - 1))); do
    OFFSET=$(($i * $BATCH_SIZE))
    BATCH_NUM=$(($i + 1))

    echo "Processing batch $BATCH_NUM/$BATCHES (cabins $OFFSET to $(($OFFSET + $BATCH_SIZE)))..."

    docker exec svakenett-postgis psql -U postgres -d svakenett -c "
    WITH batch_cabins AS (
        SELECT id, geometry
        FROM cabins
        ORDER BY id
        LIMIT $BATCH_SIZE OFFSET $OFFSET
    ),
    nearest_assignments AS (
        SELECT DISTINCT ON (bc.id)
            bc.id as cabin_id,
            gc.company_code
        FROM batch_cabins bc
        JOIN grid_companies gc
            ON ST_DWithin(bc.geometry, gc.service_area_polygon, 1.0)
        WHERE gc.service_area_polygon IS NOT NULL
        ORDER BY bc.id, ST_Distance(bc.geometry, gc.service_area_polygon)
    )
    UPDATE cabins c
    SET grid_company_code = na.company_code
    FROM nearest_assignments na
    WHERE c.id = na.cabin_id;
    " > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "  ✓ Batch $BATCH_NUM complete"
    else
        echo "  ✗ Batch $BATCH_NUM failed"
    fi
done

echo ""
echo "Batch processing complete! Verifying results..."
echo ""

# Show results
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    COUNT(*) as total_cabins,
    COUNT(grid_company_code) as cabins_with_company,
    COUNT(*) - COUNT(grid_company_code) as cabins_without_company,
    ROUND(100.0 * COUNT(grid_company_code) / COUNT(*), 1) as coverage_percent
FROM cabins;
"

echo ""
echo "Top 10 grid companies by cabin count:"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT
    gc.company_name,
    gc.company_code,
    COUNT(c.id) as cabin_count
FROM cabins c
JOIN grid_companies gc ON c.grid_company_code = gc.company_code
GROUP BY gc.company_name, gc.company_code
ORDER BY COUNT(c.id) DESC
LIMIT 10;
"

echo ""
echo "=========================================="
echo "[OK] Batch processing complete!"
echo "=========================================="
