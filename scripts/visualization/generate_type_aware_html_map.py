#!/usr/bin/env python3
"""
Generate HTML interactive map with type-aware weak grid prospects
Includes:
- 5 building types with different symbols/colors
- Power lines layer
- Transformers layer
- Type-aware popups
- Layer controls
- Marker clustering for performance
"""

import psycopg2
import folium
from folium import plugins
import json
from collections import defaultdict

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'svakenett',
    'user': 'postgres'
}

# Output file
OUTPUT_FILE = "/mnt/c/Users/klaus/klauspython/svakenett/data/processed/unified_buildings_2025-11-24/weak_grid_map_type_aware.html"

# Building type configuration
BUILDING_TYPES = {
    161: {
        'name': 'Fritidsbygg (Cabins)',
        'color': '#8B4513',  # Brown
        'icon': 'home',
        'threshold': 70
    },
    111: {
        'name': 'Enebolig (Single-family)',
        'color': '#2E8B57',  # Green
        'icon': 'home',
        'threshold': 80
    },
    112: {
        'name': 'Tomannsbolig (Duplex)',
        'color': '#4169E1',  # Blue
        'icon': 'building',
        'threshold': 82
    },
    113: {
        'name': 'Rekkehus (Townhouse)',
        'color': '#FF8C00',  # Orange
        'icon': 'building',
        'threshold': 85
    },
    121: {
        'name': 'Våningshus (Apartment)',
        'color': '#DC143C',  # Red
        'icon': 'building',
        'threshold': 85
    }
}

print("=" * 70)
print("Generating Type-Aware HTML Visualization")
print("=" * 70)

# Connect to database
conn = psycopg2.connect(**DB_CONFIG)
cur = conn.cursor()

# Create base map centered on Agder
print("\n1. Creating base map...")
m = folium.Map(
    location=[58.5, 7.8],  # Agder region center
    zoom_start=8,
    tiles='OpenStreetMap'
)

# ===========================================================================
# Layer 1-5: Building types with marker clustering
# ===========================================================================
print("\n2. Fetching buildings by type...")

for bygningstype, config in BUILDING_TYPES.items():
    print(f"   - Processing {config['name']}...")

    # Create marker cluster for this building type
    cluster = plugins.MarkerCluster(
        name=f"{config['name']} (threshold ≥ {config['threshold']})",
        overlay=True,
        control=True,
        show=True if bygningstype == 161 else False  # Show cabins by default
    )

    # Fetch buildings of this type meeting threshold
    cur.execute("""
        SELECT
            id,
            weak_grid_score,
            distance_to_line_m,
            grid_density_lines_1km,
            voltage_level_kv,
            grid_age_years,
            postal_code,
            ST_Y(geometry) as latitude,
            ST_X(geometry) as longitude
        FROM buildings
        WHERE bygningstype = %s
          AND weak_grid_score >= %s
        ORDER BY weak_grid_score DESC
        LIMIT 5000  -- Limit for performance
    """, (bygningstype, config['threshold']))

    buildings = cur.fetchall()
    print(f"     Found {len(buildings)} prospects (showing up to 5000)")

    # Add markers to cluster
    for building in buildings:
        (bid, score, dist, density, voltage, age, postal, lat, lon) = building

        # Create popup with building info
        popup_html = f"""
        <div style="font-family: Arial; font-size: 12px;">
            <h4 style="margin: 0 0 10px 0; color: {config['color']};">
                {config['name']}
            </h4>
            <table style="width: 100%;">
                <tr><td><b>Building ID:</b></td><td>{bid}</td></tr>
                <tr><td><b>Weak Grid Score:</b></td><td><b>{score:.1f}</b></td></tr>
                <tr><td><b>Distance to line:</b></td><td>{dist:.0f} m</td></tr>
                <tr><td><b>Grid density:</b></td><td>{density} lines/km</td></tr>
                <tr><td><b>Voltage level:</b></td><td>{voltage} kV</td></tr>
                <tr><td><b>Grid age:</b></td><td>{f'{age:.0f} years' if age else 'N/A'}</td></tr>
                <tr><td><b>Postal code:</b></td><td>{postal or 'N/A'}</td></tr>
            </table>
            <p style="margin: 10px 0 0 0; padding: 5px; background-color: #f0f0f0; border-radius: 3px;">
                <b>Assessment:</b> High prospect for solar+battery
            </p>
        </div>
        """

        # Add marker to cluster
        folium.Marker(
            location=[lat, lon],
            popup=folium.Popup(popup_html, max_width=300),
            icon=folium.Icon(
                color='red' if score >= config['threshold'] + 10 else 'orange',
                icon=config['icon'],
                prefix='fa'
            )
        ).add_to(cluster)

    # Add cluster to map
    cluster.add_to(m)

# ===========================================================================
# Layer 6: Power Lines
# ===========================================================================
print("\n3. Adding power lines layer...")

# Fetch power lines
cur.execute("""
    SELECT
        id,
        spenning_kv as voltage_kv,
        eierorgnr as owner_orgnr,
        driftsattaar as year_built,
        ST_AsGeoJSON(geometry) as geojson
    FROM power_lines_new
    -- All lines included (9,715 total)
""")

power_lines = cur.fetchall()
print(f"   Adding {len(power_lines)} power lines...")

# Create feature group for power lines
power_lines_layer = folium.FeatureGroup(
    name="Power Lines (Kraftlinjer)",
    overlay=True,
    control=True,
    show=True  # Visible by default
)

for line in power_lines:
    (lid, voltage, owner, year, geojson) = line

    # Parse GeoJSON
    geom = json.loads(geojson)
    coords = geom['coordinates']

    # Determine color by voltage
    if voltage is not None and voltage >= 132:
        color = '#FF0000'  # Red for high voltage (≥132 kV)
        weight = 3
    elif voltage is not None and voltage >= 33:
        color = '#FFA500'  # Orange for medium voltage (33-132 kV)
        weight = 2
    elif voltage is not None and 11 <= voltage <= 24:
        color = '#FF0000'  # Red for distribution (11-24 kV) - thinner
        weight = 1.5
    else:
        color = '#CCCCCC'  # Gray for other/unknown voltage
        weight = 1

    # Add line to layer
    if geom['type'] == 'LineString':
        # Convert coordinates from [lon, lat] to [lat, lon]
        line_coords = [[c[1], c[0]] for c in coords]

        folium.PolyLine(
            locations=line_coords,
            color=color,
            weight=weight,
            opacity=0.6,
            popup=f"Line ID: {lid}<br>Voltage: {voltage} kV<br>Owner: {owner or 'N/A'}<br>Built: {year or 'Unknown'}"
        ).add_to(power_lines_layer)
    elif geom['type'] == 'MultiLineString':
        # MultiLineString has multiple line segments
        for line_segment in coords:
            # Convert coordinates from [lon, lat] to [lat, lon]
            line_coords = [[c[1], c[0]] for c in line_segment]

            folium.PolyLine(
                locations=line_coords,
                color=color,
                weight=weight,
                opacity=0.6,
                popup=f"Line ID: {lid}<br>Voltage: {voltage} kV<br>Owner: {owner or 'N/A'}<br>Built: {year or 'Unknown'}"
            ).add_to(power_lines_layer)

power_lines_layer.add_to(m)

# ===========================================================================
# Layer 7: Transformers
# ===========================================================================
print("\n4. Adding transformers layer...")

# Fetch transformers
cur.execute("""
    SELECT
        id,
        spenning_kv as voltage_kv,
        eierorgnr as owner_orgnr,
        ST_Y(geometry) as latitude,
        ST_X(geometry) as longitude
    FROM transformers_new
""")

transformers = cur.fetchall()
print(f"   Adding {len(transformers)} transformers...")

# Create feature group for transformers
transformers_layer = folium.FeatureGroup(
    name="Transformers (Transformatorer)",
    overlay=True,
    control=True,
    show=False  # Hidden by default
)

for transformer in transformers:
    (tid, voltage, owner, lat, lon) = transformer

    folium.CircleMarker(
        location=[lat, lon],
        radius=5,
        color='#800080',  # Purple
        fill=True,
        fillColor='#800080',
        fillOpacity=0.7,
        popup=f"Transformer ID: {tid}<br>Voltage: {voltage} kV<br>Owner: {owner or 'N/A'}"
    ).add_to(transformers_layer)

transformers_layer.add_to(m)

# ===========================================================================
# Add layer control and legend
# ===========================================================================
print("\n5. Adding layer control and legend...")

# Add layer control
folium.LayerControl(position='topright', collapsed=False).add_to(m)

# Add custom legend
legend_html = """
<div style="position: fixed;
            bottom: 50px; left: 50px; width: 300px; height: auto;
            background-color: white; border:2px solid grey; z-index:9999;
            font-size:14px; padding: 10px; border-radius: 5px;">
    <h4 style="margin: 0 0 10px 0;">Weak Grid Prospects - Type-Aware</h4>

    <p style="margin: 5px 0;"><b>Building Types:</b></p>
    <p style="margin: 2px 0; padding-left: 10px;">
        <i class="fa fa-home" style="color: #8B4513;"></i> Cabins (threshold ≥ 70)<br>
        <i class="fa fa-home" style="color: #2E8B57;"></i> Single-family (threshold ≥ 80)<br>
        <i class="fa fa-building" style="color: #4169E1;"></i> Duplexes (threshold ≥ 82)<br>
        <i class="fa fa-building" style="color: #FF8C00;"></i> Townhouses (threshold ≥ 85)<br>
        <i class="fa fa-building" style="color: #DC143C;"></i> Apartments (threshold ≥ 85)
    </p>

    <p style="margin: 10px 0 5px 0;"><b>Power Infrastructure:</b></p>
    <p style="margin: 2px 0; padding-left: 10px;">
        <span style="color: #FF0000; font-weight: bold;">━━━</span> High voltage (≥132 kV)<br>
        <span style="color: #FFA500;">━━━</span> Medium voltage (33-132 kV)<br>
        <span style="color: #FF0000;">━━</span> Distribution (11-24 kV)<br>
        <span style="color: #CCCCCC;">━━━</span> Other/Unknown<br>
        <span style="color: #800080;">●</span> Transformers
    </p>

    <p style="margin: 10px 0 0 0; font-size: 11px; color: #666;">
        Showing up to 5,000 highest-scoring prospects per type
    </p>
</div>
"""

m.get_root().html.add_child(folium.Element(legend_html))

# ===========================================================================
# Save map
# ===========================================================================
print(f"\n6. Saving map to {OUTPUT_FILE}...")
m.save(OUTPUT_FILE)

# Close database connection
cur.close()
conn.close()

print("\n" + "=" * 70)
print("✓ HTML Map Generated Successfully")
print("=" * 70)
print(f"\nFile: {OUTPUT_FILE}")
print("\nMap includes:")
print("  - 5 building type layers with type-aware thresholds")
print("  - Power lines layer (up to 10,000 lines)")
print("  - Transformers layer (106 transformers)")
print("  - Marker clustering for performance")
print("  - Layer controls to toggle visibility")
print("  - Custom legend with thresholds")
print("\nOpen in browser to view interactive map")
