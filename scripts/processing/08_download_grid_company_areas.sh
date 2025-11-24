#!/bin/bash
# Download grid company service areas from NVE ArcGIS REST service

OUTPUT_FILE="data/grid_companies/service_areas.geojson"
NVE_URL="https://nve.geodataonline.no/arcgis/rest/services/Nettanlegg4/MapServer/6/query"

echo "=========================================="
echo "Downloading Grid Company Service Areas from NVE"
echo "=========================================="

# Create directory
mkdir -p data/grid_companies

echo ""
echo "1. Downloading service areas for EIERTYPE='EVERK' (grid companies)..."
echo "   Source: NVE Nettanlegg4 MapServer"

# Query parameters:
# - where: EIERTYPE='EVERK' (filter for grid companies)
# - outFields: * (all fields)
# - returnGeometry: true
# - f: geojson (output format)
# - outSR: 4326 (WGS84 for compatibility)

QUERY_URL="${NVE_URL}?where=EIERTYPE%3D%27EVERK%27&outFields=*&returnGeometry=true&f=geojson&outSR=4326"

curl -s "$QUERY_URL" -o "$OUTPUT_FILE"

# Check if download successful
if [ -f "$OUTPUT_FILE" ]; then
    echo "   Download complete!"

    # Show file size
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo "   File size: $FILE_SIZE"

    # Count features
    FEATURE_COUNT=$(grep -o '"type":"Feature"' "$OUTPUT_FILE" | wc -l)
    echo "   Features downloaded: $FEATURE_COUNT"

    # Show sample company names
    echo ""
    echo "2. Sample grid companies in dataset:"
    python3 << 'EOF'
import json

with open('data/grid_companies/service_areas.geojson', 'r') as f:
    data = json.load(f)

print(f"   Total features: {len(data['features'])}")
print("")
print("   First 10 companies:")
for i, feature in enumerate(data['features'][:10], 1):
    navn = feature['properties'].get('NAVN', 'N/A')
    eier_id = feature['properties'].get('EIER_ID', 'N/A')
    print(f"   {i}. {navn} (ID: {eier_id})")
EOF

else
    echo "   Error: Download failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "[OK] Service areas downloaded successfully!"
echo "=========================================="
