#!/usr/bin/env python3
"""
Analyze building types in Matrikkelen data to find bolighus vs fritidsbygg
"""

import subprocess
import json

GDB_PATH = "/mnt/c/users/klaus/klauspython/qgis/svakenett/matrikkelen_data/Basisdata_42_Agder_25833_MatrikkelenBygning_FGDB.gdb"

print("Analyzing building types in Matrikkelen...")
print("=" * 60)

# Use ogr2ogr SQL to get building type counts
cmd = [
    "ogrinfo",
    "-q",
    "-sql",
    "SELECT bygningstype, COUNT(*) as count FROM bygning GROUP BY bygningstype ORDER BY count DESC",
    GDB_PATH
]

result = subprocess.run(cmd, capture_output=True, text=True)

print("\nBuilding Type Distribution:")
print("-" * 60)
print(result.stdout)

# Mapping of building type codes (from Matrikkelen documentation)
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

print("\n\nBuilding Type Codes:")
print("-" * 60)
for code, name in sorted(BYGNINGSTYPER.items()):
    print(f"{code}: {name}")
