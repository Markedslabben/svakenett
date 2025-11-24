#!/usr/bin/env python3
"""
Count building types in Matrikkelen using simple attribute read
"""

import fiona
from collections import Counter

GDB_PATH = "/mnt/c/users/klaus/klauspython/qgis/svakenett/matrikkelen_data/Basisdata_42_Agder_25833_MatrikkelenBygning_FGDB.gdb"

print("Counting building types in Matrikkelen...")
print("=" * 60)

# Mapping of building type codes
BYGNINGSTYPER = {
    111: "Enebolig",
    112: "Tomannsbolig",
    113: "Rekkehus",
    121: "Våningshus",
    131: "Sykehjem/aldershjem",
    161: "Fritidsbygg (hytte)",
    163: "Anneks til bolig/fritidsbolig",
    171: "Garasje/uthus",
    181: "Næringsbygg",
}

# Count building types
type_counts = Counter()
total = 0

with fiona.open(GDB_PATH, layer='bygning') as src:
    print(f"Total features: {len(src)}")

    for i, feature in enumerate(src):
        if i % 50000 == 0:
            print(f"  Processed {i:,}...")

        bygningstype = feature['properties'].get('bygningstype')
        if bygningstype:
            type_counts[bygningstype] += 1
        total += 1

print(f"\nTotal buildings processed: {total:,}")
print("\n" + "=" * 60)
print("Building Type Distribution:")
print("=" * 60)

# Sort by count
for bygtype, count in sorted(type_counts.items(), key=lambda x: x[1], reverse=True):
    name = BYGNINGSTYPER.get(bygtype, f"Unknown ({bygtype})")
    pct = 100.0 * count / total
    print(f"{bygtype:3d} - {name:30s}: {count:7,} ({pct:5.1f}%)")

print("=" * 60)

# Calculate relevant categories
hytter = type_counts.get(161, 0)
boliger = sum(type_counts.get(t, 0) for t in [111, 112, 113, 121])

print(f"\nSummary:")
print(f"  Fritidsbygg (hytter):     {hytter:7,} ({100.0*hytter/total:5.1f}%)")
print(f"  Boliger (111-113, 121):   {boliger:7,} ({100.0*boliger/total:5.1f}%)")
print(f"  Andre:                    {total-hytter-boliger:7,} ({100.0*(total-hytter-boliger)/total:5.1f}%)")
