#!/usr/bin/env python3
"""
Process NVE KILE data and prepare for database loading
"""

import pandas as pd
import sys
from pathlib import Path

# File paths
EXCEL_2025 = "data/kile/grunnlagsdata_ir_2025.xlsx"
EXCEL_2024 = "data/kile/grunnlagsdata_ir_2024.xlsx"
OUTPUT_CSV = "data/kile/grid_companies_kile.csv"

def main():
    print("=" * 70)
    print("Processing NVE KILE Data")
    print("=" * 70)

    # Read 2025 data (most recent)
    print(f"\n1. Loading {EXCEL_2025}...")
    df = pd.read_excel(EXCEL_2025)

    print(f"   Loaded {len(df)} rows")

    # Remove first row (contains metadata labels, not data)
    df = df[df['Årstall'] != 'y'].copy()

    # Convert year to numeric
    df['Årstall'] = pd.to_numeric(df['Årstall'], errors='coerce')

    # Filter for most recent year
    most_recent_year = int(df['Årstall'].max())
    print(f"\n2. Filtering for most recent year: {most_recent_year}")
    df_recent = df[df['Årstall'] == most_recent_year].copy()
    print(f"   {len(df_recent)} companies in {most_recent_year}")

    # Calculate total KILE (sum of Dnett, Rnett, Tnett)
    print("\n3. Calculating total KILE costs...")

    # Convert KILE columns to numeric
    kile_cols = ['KILE \nDnett', 'KILE \nRnett', 'KILE \nTnett', 'Antall abonnementer']
    for col in kile_cols:
        df_recent[col] = pd.to_numeric(df_recent[col], errors='coerce').fillna(0)

    df_recent['kile_total'] = (
        df_recent['KILE \nDnett'] +
        df_recent['KILE \nRnett'] +
        df_recent['KILE \nTnett']
    )

    # Select relevant columns and rename
    df_companies = df_recent[[
        'Organisasjonsnummer',
        'Selskapsnavn',
        'Årstall',
        'KILE \nDnett',
        'KILE \nRnett',
        'KILE \nTnett',
        'kile_total',
        'Antall abonnementer'
    ]].copy()

    # Rename columns for easier handling
    df_companies.columns = [
        'org_number',
        'company_name',
        'year',
        'kile_dnett',
        'kile_rnett',
        'kile_tnett',
        'kile_total',
        'num_customers'
    ]

    # Filter out companies with no customers
    df_companies = df_companies[df_companies['num_customers'] > 0].copy()

    # Calculate KILE per customer (quality metric)
    df_companies['kile_per_customer'] = (
        df_companies['kile_total'] / df_companies['num_customers']
    ).round(2)

    # Sort by KILE per customer (worst first)
    df_companies = df_companies.sort_values('kile_per_customer', ascending=False)

    # Save to CSV
    print(f"\n4. Saving to {OUTPUT_CSV}...")
    output_path = Path(OUTPUT_CSV)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_companies.to_csv(OUTPUT_CSV, index=False, encoding='utf-8')

    print(f"\n5. Summary Statistics:")
    print(f"   Total companies: {len(df_companies)}")
    print(f"   Year: {most_recent_year}")
    print(f"   Total KILE costs: {df_companies['kile_total'].sum():,.0f} NOK")
    print(f"   Average KILE per customer: {df_companies['kile_per_customer'].mean():.2f} NOK")

    print(f"\n6. Top 10 companies by KILE per customer (worst reliability):")
    print(df_companies[['company_name', 'num_customers', 'kile_total', 'kile_per_customer']].head(10).to_string(index=False))

    print(f"\n7. Bottom 10 companies by KILE per customer (best reliability):")
    print(df_companies[['company_name', 'num_customers', 'kile_total', 'kile_per_customer']].tail(10).to_string(index=False))

    print("\n" + "=" * 70)
    print("✓ KILE data processing complete!")
    print("=" * 70)
    print(f"\nNext step: Load {OUTPUT_CSV} into PostgreSQL")

if __name__ == "__main__":
    main()
