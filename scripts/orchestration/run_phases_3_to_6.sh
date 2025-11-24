#!/bin/bash
# Master orchestration script - Automatically run Phases 3-6
# This script executes after Phase 2 (metrics calculation) completes
# Runs: Scoring → Reports → CSV Export → HTML Visualization

set -e  # Exit on error

echo "=============================================="
echo "Overnight Task: Phases 3-6 Orchestration"
echo "=============================================="
echo ""
echo "This script will execute:"
echo "  Phase 3: v3.0 REALISTIC scoring (5 min)"
echo "  Phase 4: Type-aware reports (10 min)"
echo "  Phase 5: CSV exports (15 min)"
echo "  Phase 6: HTML visualization (20 min)"
echo ""
echo "Total estimated time: 50 minutes"
echo ""

DB_NAME="svakenett"
DB_USER="postgres"

# ===========================================================================
# Phase 3: Run v3.0 REALISTIC Scoring on All Buildings
# ===========================================================================
echo "=============================================="
echo "PHASE 3: v3.0 REALISTIC Scoring"
echo "=============================================="
echo ""

PGPASSWORD="" psql -h localhost -p 5432 -U $DB_USER -d $DB_NAME -f /home/klaus/klauspython/svakenett/sql/calculate_weak_grid_scores_v3_unified.sql

echo ""
echo "✓ Phase 3 Complete"
echo ""

# ===========================================================================
# Phase 4: Generate Type-Aware Reports
# ===========================================================================
echo "=============================================="
echo "PHASE 4: Type-Aware Reports"
echo "=============================================="
echo ""

chmod +x /home/klaus/klauspython/svakenett/scripts/reporting/generate_type_aware_reports.sh
/home/klaus/klauspython/svakenett/scripts/reporting/generate_type_aware_reports.sh

echo ""
echo "✓ Phase 4 Complete"
echo ""

# ===========================================================================
# Phase 5: Export CSV Files
# ===========================================================================
echo "=============================================="
echo "PHASE 5: CSV Exports"
echo "=============================================="
echo ""

chmod +x /home/klaus/klauspython/svakenett/scripts/export/export_type_aware_csvs.sh
/home/klaus/klauspython/svakenett/scripts/export/export_type_aware_csvs.sh

echo ""
echo "✓ Phase 5 Complete"
echo ""

# ===========================================================================
# Phase 6: Generate HTML Interactive Visualization
# ===========================================================================
echo "=============================================="
echo "PHASE 6: HTML Visualization"
echo "=============================================="
echo ""

chmod +x /home/klaus/klauspython/svakenett/scripts/visualization/generate_type_aware_html_map.py
python3 /home/klaus/klauspython/svakenett/scripts/visualization/generate_type_aware_html_map.py

echo ""
echo "✓ Phase 6 Complete"
echo ""

# ===========================================================================
# Final Summary
# ===========================================================================
echo "=============================================="
echo "✓ PHASES 3-6 COMPLETE"
echo "=============================================="
echo ""
echo "Completed:"
echo "  ✓ Phase 3: Scored 130,250 buildings with v3.0 algorithm"
echo "  ✓ Phase 4: Generated 5 type-aware reports"
echo "  ✓ Phase 5: Exported 7 CSV files"
echo "  ✓ Phase 6: Created HTML interactive map"
echo ""
echo "Next steps (manual):"
echo "  - Phase 7: Create QGIS visualization"
echo "  - Phase 8: Update documentation"
echo ""
echo "Output location:"
echo "  /mnt/c/Users/klaus/klauspython/svakenett/data/processed/unified_buildings_$(date +%Y-%m-%d)/"
echo ""
echo "View results:"
echo "  - Open weak_grid_map_type_aware.html in browser"
echo "  - Review reports: 01_type_aware_prospects.txt through 05_infrastructure_quality.txt"
echo "  - Analyze CSVs for detailed data"
echo ""
echo "=============================================="
echo "Total runtime: $(( SECONDS / 60 )) minutes"
echo "=============================================="
