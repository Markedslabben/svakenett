#!/usr/bin/env python3
"""
Generate interactive weak grid map with voltage-adjusted scores
Uses CSV export with NEW scores from REVISED methodology
"""
import pandas as pd
import folium
from folium.plugins import MarkerCluster
import os

# Read CSV with revised scores
df = pd.read_csv('weak_grid_data_REVISED.csv')

print(f"Loading {len(df)} weak grid buildings...")

# Calculate center of map
center_lat = df['latitude'].mean()
center_lon = df['longitude'].mean()

# Create map centered on Agder region
m = folium.Map(
    location=[center_lat, center_lon],
    zoom_start=8,
    tiles='OpenStreetMap'
)

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

# Create marker cluster for better performance with many points
marker_cluster = MarkerCluster(name='Weak Grid Buildings').add_to(m)

# Limit to top 1000 buildings for performance
top_buildings = df.nlargest(1000, 'weak_grid_score')

print(f"Plotting top {len(top_buildings)} buildings...")

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
        radius=4,
        popup=folium.Popup(popup_html, max_width=350),
        color=get_color(row['weak_grid_score']),
        fillColor=get_color(row['weak_grid_score']),
        fillOpacity=0.7,
        weight=1
    ).add_to(marker_cluster)

# Add layer control
folium.LayerControl().add_to(m)

# Add legend explaining NEW voltage-adjusted scoring
legend_html = '''
<div style="position: fixed;
     bottom: 50px; left: 50px; width: 250px; height: 200px;
     background-color: white; border:2px solid grey; z-index:9999;
     font-size:13px; padding: 10px; font-family: Arial, sans-serif;">
     <p style="margin: 0 0 10px 0;"><b>Weak Grid Score (REVISED)</b></p>
     <p style="font-size: 11px; color: #666; margin: 0 0 10px 0;">
        Voltage-adjusted thresholds:<br>
        22kV: 15km | 11kV: 8km
     </p>
     <p style="margin: 3px 0;"><i style="background:darkred; width:15px; height:10px; display:inline-block; margin-right:5px;"></i> 70-77 (Top Tier 2)</p>
     <p style="margin: 3px 0;"><i style="background:red; width:15px; height:10px; display:inline-block; margin-right:5px;"></i> 60-69 (Tier 2)</p>
     <p style="margin: 3px 0;"><i style="background:orange; width:15px; height:10px; display:inline-block; margin-right:5px;"></i> 50-59 (High Tier 3)</p>
     <p style="margin: 3px 0;"><i style="background:yellow; width:15px; height:10px; display:inline-block; margin-right:5px;"></i> 40-49 (Tier 3)</p>
     <p style="margin: 3px 0;"><i style="background:lightgray; width:15px; height:10px; display:inline-block; margin-right:5px;"></i> 0-39 (Tier 4+5)</p>
     <p style="font-size: 10px; color: #999; margin-top: 10px;">
        OLD 2km → NEW voltage-based
     </p>
</div>
'''
m.get_root().html.add_child(folium.Element(legend_html))

# Save map
output_file = 'weak_grid_map_REVISED.html'
m.save(output_file)

print(f"\n✓ Map saved to: {output_file}")
print(f"  Total buildings in CSV: {len(df)}")
print(f"  Buildings plotted: {len(top_buildings)}")
print(f"  Score range (NEW): {df['weak_grid_score'].min():.1f} - {df['weak_grid_score'].max():.1f}")
print(f"  Score range (OLD): {df['weak_grid_score_old'].min():.1f} - {df['weak_grid_score_old'].max():.1f}")
print(f"\nOpen the map in your browser to explore the voltage-adjusted weak grid scores!")
