#!/usr/bin/env python3
"""
Load KILE data from CSV into PostgreSQL
"""

import pandas as pd
from sqlalchemy import create_engine, text

# Database connection
DATABASE_URL = 'postgresql://postgres:weakgrid2024@localhost:5432/svakenett'
CSV_FILE = 'data/kile/grid_companies_kile.csv'

def main():
    print("=" * 70)
    print("Loading KILE Data into PostgreSQL")
    print("=" * 70)

    # Read CSV
    print(f"\n1. Reading {CSV_FILE}...")
    df = pd.read_csv(CSV_FILE)
    print(f"   Found {len(df)} companies")

    # Create database connection
    print("\n2. Connecting to database...")
    engine = create_engine(DATABASE_URL)

    # Clear existing data
    print("\n3. Clearing existing grid_companies data...")
    with engine.connect() as conn:
        result = conn.execute(text("DELETE FROM grid_companies"))
        conn.commit()
        print(f"   Deleted {result.rowcount} existing records")

    # Prepare data for insertion
    print("\n4. Preparing data...")
    df_load = pd.DataFrame({
        'company_code': df['org_number'].astype(str),
        'company_name': df['company_name'],
        'kile_cost_nok': df['kile_total'],
        'num_customers': df['num_customers'].astype(int),
        'kile_per_customer': df['kile_per_customer']
    })

    # Load to database
    print("\n5. Loading data to grid_companies table...")
    df_load.to_sql(
        'grid_companies',
        engine,
        if_exists='append',
        index=False,
        method='multi',
        chunksize=1000
    )

    # Verify
    print("\n6. Verifying data...")
    with engine.connect() as conn:
        result = conn.execute(text("SELECT COUNT(*) as count FROM grid_companies"))
        count = result.scalar()
        print(f"   {count} companies loaded successfully!")

        # Show top 5 worst reliability
        print("\n7. Top 5 worst reliability (highest KILE per customer):")
        result = conn.execute(text("""
            SELECT company_name, num_customers, kile_cost_nok, kile_per_customer
            FROM grid_companies
            ORDER BY kile_per_customer DESC
            LIMIT 5
        """))
        for row in result:
            print(f"   {row.company_name[:40]:40s} | {row.kile_per_customer:8.2f} NOK/customer")

    print("\n" + "=" * 70)
    print("[OK] KILE data loaded successfully!")
    print("=" * 70)

if __name__ == "__main__":
    main()
