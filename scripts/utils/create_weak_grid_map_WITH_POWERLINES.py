#!/usr/bin/env python3
"""
Generate interactive weak grid map WITH POWER LINES
Shows voltage-adjusted scores + NVE power line infrastructure
"""
import pandas as pd
import folium
from folium.plugins import MarkerCluster
import psycopg2
from psycopg2.extras import RealDictCursor

print("Loading weak grid buildings and power lines...")

# Read CSV with revised scores
df_buildings = pd.read_csv('weak_grid_data_REVISED.csv')
print(f"  ✓ Loaded {len(df_buildings)} weak grid buildings")

# Connect to database to get power lines
conn = psycopg2.connect(dbname="svakenett", port=5433)
cur = conn.cursor(cursor_factory=RealDictCursor)

# Get power lines in Agder region (network level 3 = distribution grid)
print("  Fetching power lines from database...")
cur.execute("""
    SELECT
        id,
        spenning_kv,
        nvenettnivaa,
        ST_AsGeoJSON(geometry) as geojson
    FROM nve_power_lines
    WHERE nvenettnivaa = 3  -- Distribution grid (22kV, 11kV)
      AND spenning_kv IN (11, 12, 22, 24)  -- Only relevant voltages
    ORDER BY spenning_kv DESC
    LIMIT 5000;  -- Limit for performance (adjust if needed)
""")

power_lines = cur.fetchall()
print(f"  ✓ Loaded {len(power_lines)} power lines")

cur.close()
conn.close()

# Calculate center of map
center_lat = df_buildings['latitude'].mean()
center_lon = df_buildings['longitude'].mean()

# Create map centered on Agder region
m = folium.Map(
    location=[center_lat, center_lon],
    zoom_start=8,
    tiles='OpenStreetMap'
)

# ============================================================================
# LAYER 1: Power Lines (underneath buildings)
# ============================================================================

print("Adding power lines to map...")

import json

# Create feature groups for different voltage levels
lines_22_24kv = folium.FeatureGroup(name='Power Lines 22-24 kV', show=True)
lines_11_12kv = folium.FeatureGroup(name='Power Lines 11-12 kV', show=True)

for line in power_lines:
    geojson_data = json.loads(line['geojson'])
    voltage = line['spenning_kv']

    # Color and style by voltage
    if voltage in [22, 24]:
        color = '#2166ac'  # Blue for 22-24 kV
        weight = 2
        layer = lines_22_24kv
    else:  # 11, 12 kV
        color = '#b2182b'  # Red for 11-12 kV
        weight = 1.5
        layer = lines_11_12kv

    folium.GeoJson(
        geojson_data,
        style_function=lambda x, color=color, weight=weight: {
            'color': color,
            'weight': weight,
            'opacity': 0.6
        },
        tooltip=f"{voltage} kV power line"
    ).add_to(layer)

# Add line layers to map
lines_22_24kv.add_to(m)
lines_11_12kv.add_to(m)

print("  ✓ Power lines added")

# ============================================================================
# LAYER 2: Weak Grid Buildings (on top of power lines)
# ============================================================================

print("Adding weak grid buildings...")

# Define color scheme for NEW scores (voltage-adjusted)
def get_color(score):
    if score >= 70:
        return 'darkred'  # Top Tier 2
    elif score >= 60:
        return 'red'      # Tier 2
    elif score >= 50:
        return 'orange'   # High Tier 3
    elif score >= 40:
        return 'yellow'   # Tier 3
    else:
        return 'lightgray'  # Tier 4+5

# Create marker cluster for buildings
marker_cluster = MarkerCluster(name='Weak Grid Buildings', show=True).add_to(m)

# Limit to top 1000 buildings for performance
top_buildings = df_buildings.nlargest(1000, 'weak_grid_score')

print(f"  Plotting top {len(top_buildings)} buildings...")

# Add markers for top buildings
for idx, row in top_buildings.iterrows():
    popup_html = f'''
    <div style="font-family: Arial, sans-serif; font-size: 12px;">
    <b>Building ID:</b> {row['id']}<br>
    <b>Score (NEW):</b> <span style="color: blue; font-weight: bold;">{row['weak_grid_score']:.1f}</span><br>
    <b>Score (OLD):</b> <span style="color: gray;">{row['weak_grid_score_old']:.1f}</span><br>
    <hr style="margin: 5px 0;">
    <b>Transformer Distance:</b> {row['nearest_transformer_m']/1000:.1f} km<br>
    <b>Line Distance:</b> {row['distance_to_line_m']:.0f} m<br>
    <b>Grid Density:</b> {row['grid_density_1km']:.0f} lines/km<br>
    <b>Voltage:</b> {row['nearest_line_voltage_kv']:.0f} kV<br>
    <b>Grid Age:</b> {row['nearest_line_age_years']:.0f} years<br>
    <hr style="margin: 5px 0;">
    <b>Municipality:</b> {row['kommunenavn']}<br>
    <b>Building Type:</b> {row['bygningstype']}
    </div>
    '''

    folium.CircleMarker(
        location=[row['latitude'], row['longitude']],
        radius=5,
        popup=folium.Popup(popup_html, max_width=350),
        color=get_color(row['weak_grid_score']),
        fillColor=get_color(row['weak_grid_score']),
        fillOpacity=0.8,
        weight=2
    ).add_to(marker_cluster)

print("  ✓ Buildings added")

# Add layer control
folium.LayerControl(collapsed=False).add_to(m)

# Add legend explaining NEW voltage-adjusted scoring AND power lines
legend_html = '''
<div style="position: fixed;
     bottom: 50px; left: 50px; width: 280px; height: 280px;
     background-color: white; border:2px solid grey; z-index:9999;
     font-size:13px; padding: 10px; font-family: Arial, sans-serif;">
     <p style="margin: 0 0 10px 0;"><b>Weak Grid Score (REVISED)</b></p>
     <p style="font-size: 11px; color: #666; margin: 0 0 10px 0;">
        Voltage-adjusted thresholds:<br>
        22kV: 15km | 11kV: 8km
     </p>
     <p style="margin: 3px 0;"><i style="background:darkred; width:15px; height:10px; display:inline-block; margin-right:5px; border-radius:50%;"></i> 70-77 (Top Tier 2)</p>
     <p style="margin: 3px 0;"><i style="background:red; width:15px; height:10px; display:inline-block; margin-right:5px; border-radius:50%;"></i> 60-69 (Tier 2)</p>
     <p style="margin: 3px 0;"><i style="background:orange; width:15px; height:10px; display:inline-block; margin-right:5px; border-radius:50%;"></i> 50-59 (High Tier 3)</p>
     <p style="margin: 3px 0;"><i style="background:yellow; width:15px; height:10px; display:inline-block; margin-right:5px; border-radius:50%;"></i> 40-49 (Tier 3)</p>
     <p style="margin: 3px 0;"><i style="background:lightgray; width:15px; height:10px; display:inline-block; margin-right:5px; border-radius:50%;"></i> 0-39 (Tier 4+5)</p>
     <hr style="margin: 10px 0;">
     <p style="margin: 0 0 5px 0;"><b>Power Lines</b></p>
     <p style="margin: 3px 0;"><i style="background:#2166ac; width:20px; height:3px; display:inline-block; margin-right:5px;"></i> 22-24 kV</p>
     <p style="margin: 3px 0;"><i style="background:#b2182b; width:20px; height:3px; display:inline-block; margin-right:5px;"></i> 11-12 kV</p>
     <p style="font-size: 10px; color: #999; margin-top: 10px;">
        Use layer control (top right) to toggle layers
     </p>
</div>
'''
m.get_root().html.add_child(folium.Element(legend_html))

# Save map
output_file = 'weak_grid_map_WITH_POWERLINES.html'
m.save(output_file)

print(f"\n✓ Enhanced map saved to: {output_file}")
print(f"  Total buildings in CSV: {len(df_buildings)}")
print(f"  Buildings plotted: {len(top_buildings)}")
print(f"  Power lines plotted: {len(power_lines)}")
print(f"  Score range (NEW): {df_buildings['weak_grid_score'].min():.1f} - {df_buildings['weak_grid_score'].max():.1f}")
print(f"  Score range (OLD): {df_buildings['weak_grid_score_old'].min():.1f} - {df_buildings['weak_grid_score_old'].max():.1f}")
print(f"\nOpen the map in your browser to explore weak grid scores with power line infrastructure!")
