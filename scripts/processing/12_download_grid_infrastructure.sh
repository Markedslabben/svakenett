#!/bin/bash
# Download NVE grid infrastructure data for Agder region
# Downloads 4 layers in parallel: power lines, poles, cables, transformers

set -e  # Exit on error

echo "=========================================="
echo "Downloading NVE Grid Infrastructure Data"
echo "=========================================="

# Create data directory
mkdir -p data/nve_infrastructure

# NVE ArcGIS REST API base URL
BASE_URL="https://nve.geodataonline.no/arcgis/rest/services/Nettanlegg4/MapServer"

# Agder region bounding box (approximate)
# West, South, East, North in EPSG:4326
BBOX="6.5,57.8,9.2,59.5"

# Function to download a layer
download_layer() {
    local layer_id=$1
    local layer_name=$2
    local output_file=$3

    echo ""
    echo "Downloading Layer $layer_id: $layer_name..."

    # Build query URL
    local query_url="${BASE_URL}/${layer_id}/query"

    # Parameters for the query
    # Filter by grid companies serving our Agder cabins
    # Company codes: 925803375, 918312730, 979399901, 980038408, 924862602, 915635857
    local company_filter="eierOrgnr IN (925803375,918312730,979399901,980038408,924862602,915635857)"
    local params="where=${company_filter// /%20}"
    params="${params}&outFields=*"
    params="${params}&returnGeometry=true"
    params="${params}&f=geojson"

    # Download with curl
    curl -f -L -o "$output_file" "${query_url}?${params}" 2>&1 | grep -v "progress"

    if [ $? -eq 0 ]; then
        # Check if file is valid GeoJSON
        if grep -q '"type":"FeatureCollection"' "$output_file" 2>/dev/null; then
            local feature_count=$(grep -o '"type":"Feature"' "$output_file" | wc -l)
            echo "✓ Downloaded $feature_count features to $output_file"
        else
            echo "✗ Error: Invalid GeoJSON received for $layer_name"
            cat "$output_file" | head -20
            return 1
        fi
    else
        echo "✗ Error downloading $layer_name"
        return 1
    fi
}

# Track PIDs for parallel execution
pids=()

# Layer 2: Distribusjonsnett (Distribution grid power lines)
download_layer 2 "Distribusjonsnett" "data/nve_infrastructure/power_lines.geojson" &
pids+=($!)

# Layer 4: Master og stolper (Poles and posts)
download_layer 4 "Master_og_stolper" "data/nve_infrastructure/power_poles.geojson" &
pids+=($!)

# Layer 3: Sjøkabler (Sea and underground cables)
download_layer 3 "Sjokabler" "data/nve_infrastructure/cables.geojson" &
pids+=($!)

# Layer 5: Transformatorstasjoner (Transformer stations)
download_layer 5 "Transformatorstasjoner" "data/nve_infrastructure/transformers.geojson" &
pids+=($!)

# Wait for all parallel downloads to complete
echo ""
echo "Waiting for parallel downloads to complete..."
failed=0
for pid in "${pids[@]}"; do
    if ! wait $pid; then
        failed=$((failed + 1))
    fi
done

if [ $failed -gt 0 ]; then
    echo ""
    echo "=========================================="
    echo "✗ ERROR: $failed download(s) failed"
    echo "=========================================="
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "Download Summary"
echo "=========================================="
echo "Files downloaded to data/nve_infrastructure/:"
ls -lh data/nve_infrastructure/*.geojson | awk '{print "  " $9 " (" $5 ")"}'

echo ""
echo "Checking feature counts:"
for file in data/nve_infrastructure/*.geojson; do
    count=$(grep -o '"type":"Feature"' "$file" | wc -l)
    basename=$(basename "$file")
    printf "  %-30s %6d features\n" "$basename" "$count"
done

echo ""
echo "=========================================="
echo "[OK] Grid infrastructure data downloaded!"
echo "=========================================="
echo ""
echo "Next step: Run ./scripts/13_load_grid_infrastructure.sh"
