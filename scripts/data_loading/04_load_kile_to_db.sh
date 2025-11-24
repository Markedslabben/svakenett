#!/bin/bash
# Load KILE data into PostgreSQL

CSV_FILE="data/kile/grid_companies_kile.csv"

echo "=========================================="
echo "Loading KILE Data into PostgreSQL"
echo "=========================================="

# Clear existing data
echo ""
echo "1. Clearing existing grid_companies data..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
DELETE FROM grid_companies;
"

# Generate SQL INSERT statements from CSV
echo ""
echo "2. Generating INSERT statements from CSV..."
tail -n +2 "$CSV_FILE" | while IFS=',' read -r org_number company_name year kile_dnett kile_rnett kile_tnett kile_total num_customers kile_per_customer; do
    # Escape single quotes in company name
    company_name=$(echo "$company_name" | sed "s/'/''/g")

    echo "INSERT INTO grid_companies (company_code, company_name, kile_cost_nok, data_year)
          VALUES ('$org_number', '$company_name', $kile_total, $year);"
done | docker exec -i svakenett-postgis psql -U postgres -d svakenett

# Verify
echo ""
echo "3. Verifying data..."
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT COUNT(*) as total_companies FROM grid_companies;
"

echo ""
echo "4. Top 5 worst reliability (highest KILE costs):"
docker exec svakenett-postgis psql -U postgres -d svakenett -c "
SELECT company_name, kile_cost_nok, data_year
FROM grid_companies
ORDER BY kile_cost_nok DESC NULLS LAST
LIMIT 5;
"

echo ""
echo "=========================================="
echo "[OK] KILE data loaded successfully!"
echo "=========================================="
