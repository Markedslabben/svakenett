#!/usr/bin/env python3
"""
Inspect postal code JSON structure
"""

import json
import sys

JSON_FILE = "data/postal_codes/postal-codes.json"

print("=" * 70)
print("Inspecting Postal Code Data")
print("=" * 70)

print(f"\n1. Loading {JSON_FILE}...")
with open(JSON_FILE, 'r', encoding='utf-8') as f:
    data = json.load(f)

print(f"   Total postal codes: {len(data)}")

# Get first postal code as example
first_code = list(data.keys())[0]
first_entry = data[first_code]

print(f"\n2. Example postal code: {first_code}")
print(f"   Keys in entry: {list(first_entry.keys())}")

print(f"\n3. Sample entry structure:")
for key, value in first_entry.items():
    if key == 'geojson' and value:
        print(f"   {key}: {type(value).__name__} (geometry type: {value.get('type', 'N/A')})")
    elif isinstance(value, dict):
        print(f"   {key}: {type(value).__name__} {list(value.keys())[:3]}")
    else:
        print(f"   {key}: {value}")

# Count postal codes with geometries
codes_with_geom = sum(1 for entry in data.values() if entry.get('geojson'))
codes_without_geom = len(data) - codes_with_geom

print(f"\n4. Geometry coverage:")
print(f"   With geometry: {codes_with_geom}")
print(f"   Without geometry: {codes_without_geom}")
print(f"   Coverage: {codes_with_geom/len(data)*100:.1f}%")

# Sample postal codes for Agder region (4xxx)
agder_codes = {k: v for k, v in data.items() if k.startswith('4')}
agder_with_geom = sum(1 for entry in agder_codes.values() if entry.get('geojson'))

print(f"\n5. Agder region (postal codes 4xxx):")
print(f"   Total codes: {len(agder_codes)}")
print(f"   With geometry: {agder_with_geom}")
print(f"   Coverage: {agder_with_geom/len(agder_codes)*100:.1f}%")

# Show first 5 Agder postal codes
print(f"\n6. First 5 Agder postal codes:")
for code in sorted(agder_codes.keys())[:5]:
    entry = agder_codes[code]
    has_geom = "✓" if entry.get('geojson') else "✗"
    print(f"   {code} - {entry.get('navn', 'N/A'):30s} {has_geom}")

print("\n" + "=" * 70)
