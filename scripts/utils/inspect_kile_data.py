#!/usr/bin/env python3
"""
Inspect NVE KILE data Excel files
"""

import sys

try:
    import pandas as pd
    import openpyxl

    excel_file = sys.argv[1] if len(sys.argv) > 1 else "data/kile/grunnlagsdata_ir_2025.xlsx"

    print(f"Inspecting: {excel_file}")
    print("=" * 60)

    # Load Excel file
    xl = pd.ExcelFile(excel_file)

    print(f"\nSheets found: {xl.sheet_names}")

    # Read first sheet
    df = pd.read_excel(excel_file, sheet_name=0)

    print(f"\nShape: {df.shape[0]} rows x {df.shape[1]} columns")
    print(f"\nColumns:")
    for i, col in enumerate(df.columns, 1):
        print(f"  {i:2d}. {col}")

    print(f"\nFirst 3 rows:")
    print(df.head(3))

    # Look for KILE-related columns
    kile_cols = [col for col in df.columns if 'kile' in col.lower() or 'saidi' in col.lower() or 'saifi' in col.lower()]
    if kile_cols:
        print(f"\nKILE-related columns found:")
        for col in kile_cols:
            print(f"  - {col}")

    # Look for company/grid company columns
    company_cols = [col for col in df.columns if any(word in col.lower() for word in ['selskap', 'nett', 'navn', 'name', 'org'])]
    if company_cols:
        print(f"\nCompany-related columns found:")
        for col in company_cols:
            print(f"  - {col}")

    print("\n" + "=" * 60)

except ImportError as e:
    print(f"Error: Required package not installed: {e}")
    print("\nPlease install required packages:")
    print("  pip install pandas openpyxl")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
