#!/bin/bash
# ============================================================================
# NVE Grid Infrastructure Data Loading - Master Pipeline
# ============================================================================
# Purpose: Orchestrate complete data loading workflow from GDB to PostgreSQL
# Author: Klaus
# Date: 2025-01-22
# ============================================================================

set -e  # Exit immediately if any command fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# CONFIGURATION
# ============================================================================

# Database connection (use environment variable or default)
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}ERROR: DATABASE_URL environment variable not set${NC}"
    echo "Please set it with:"
    echo "  export DATABASE_URL='postgresql://user:password@localhost:5432/svakenett'"
    exit 1
fi

# Project root directory
PROJECT_ROOT="/mnt/c/Users/klaus/klauspython/svakenett"
SQL_DIR="$PROJECT_ROOT/sql"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Log file
LOG_FILE="$PROJECT_ROOT/logs/nve_load_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$PROJECT_ROOT/logs"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌${NC} $1" | tee -a "$LOG_FILE"
}

separator() {
    echo -e "${BLUE}========================================${NC}" | tee -a "$LOG_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

preflight_checks() {
    log "Running pre-flight checks..."

    # Check Python is available
    if ! command -v python3 &> /dev/null; then
        error "Python3 not found"
        exit 1
    fi
    success "Python3 found: $(python3 --version)"

    # Check psql is available
    if ! command -v psql &> /dev/null; then
        error "psql (PostgreSQL client) not found"
        exit 1
    fi
    success "psql found: $(psql --version)"

    # Check Python dependencies
    python3 -c "import geopandas, fiona, sqlalchemy" 2>/dev/null
    if [ $? -eq 0 ]; then
        success "Python dependencies OK (geopandas, fiona, sqlalchemy)"
    else
        error "Missing Python dependencies"
        echo "Install with: conda install -c conda-forge geopandas fiona sqlalchemy"
        exit 1
    fi

    # Check database connection
    psql "$DATABASE_URL" -c "SELECT postgis_version();" &>/dev/null
    if [ $? -eq 0 ]; then
        success "Database connection OK"
    else
        error "Cannot connect to database"
        exit 1
    fi

    # Check GDB file exists
    GDB_PATH="/mnt/c/Users/klaus/klauspython/svakenett/data/nve_infrastructure/NVEData.gdb"
    if [ -d "$GDB_PATH" ]; then
        success "NVE GDB file found"
    else
        error "NVE GDB file not found at $GDB_PATH"
        exit 1
    fi

    echo ""
}

# ============================================================================
# MAIN PIPELINE
# ============================================================================

main() {
    separator
    log "NVE Grid Infrastructure Data Loading Pipeline"
    separator
    log "Start time: $(date)"
    log "Log file: $LOG_FILE"
    echo ""

    # Pre-flight checks
    preflight_checks

    # ========================================================================
    # STEP 1: Create Database Schema
    # ========================================================================
    separator
    log "[1/7] Creating PostgreSQL schema..."
    separator

    if psql "$DATABASE_URL" -f "$SQL_DIR/nve_infrastructure_schema.sql" >> "$LOG_FILE" 2>&1; then
        success "Schema created successfully"
    else
        error "Schema creation failed - check log file"
        exit 1
    fi
    echo ""

    # ========================================================================
    # STEP 2: Load Power Lines (Kraftlinje + Sjokabel)
    # ========================================================================
    separator
    log "[2/7] Loading power lines from GDB..."
    separator

    if python3 "$SCRIPTS_DIR/load_nve_power_lines.py" | tee -a "$LOG_FILE"; then
        success "Power lines loaded successfully"
    else
        error "Power lines loading failed"
        exit 1
    fi
    echo ""

    # ========================================================================
    # STEP 3: Load Power Poles (Mast)
    # ========================================================================
    separator
    log "[3/7] Loading power poles..."
    separator

    if python3 "$SCRIPTS_DIR/load_nve_power_poles.py" | tee -a "$LOG_FILE"; then
        success "Power poles loaded successfully"
    else
        error "Power poles loading failed"
        exit 1
    fi
    echo ""

    # ========================================================================
    # STEP 4: Load Transformer Stations
    # ========================================================================
    separator
    log "[4/7] Loading transformer stations..."
    separator

    if python3 "$SCRIPTS_DIR/load_nve_transformers.py" | tee -a "$LOG_FILE"; then
        success "Transformers loaded successfully"
    else
        error "Transformer loading failed"
        exit 1
    fi
    echo ""

    # ========================================================================
    # STEP 5: Validate Data Load
    # ========================================================================
    separator
    log "[5/7] Validating data integrity..."
    separator

    if psql "$DATABASE_URL" -f "$SCRIPTS_DIR/validate_nve_load.sql" | tee -a "$LOG_FILE"; then
        success "Validation complete"
    else
        warning "Validation reported issues - review output"
    fi
    echo ""

    # ========================================================================
    # STEP 6: Calculate Cabin-to-Grid Distances
    # ========================================================================
    separator
    log "[6/7] Calculating cabin-to-grid distances..."
    separator
    warning "This step may take 10-30 minutes for ~15,000 cabins"

    if psql "$DATABASE_URL" -f "$SCRIPTS_DIR/calculate_cabin_grid_distances.sql" | tee -a "$LOG_FILE"; then
        success "Cabin distances calculated"
    else
        error "Distance calculation failed"
        exit 1
    fi
    echo ""

    # ========================================================================
    # STEP 7: Calculate Weak Grid Scores
    # ========================================================================
    separator
    log "[7/7] Calculating weak grid scores..."
    separator

    if psql "$DATABASE_URL" -f "$SCRIPTS_DIR/calculate_weak_grid_scores.sql" | tee -a "$LOG_FILE"; then
        success "Weak grid scores calculated"
    else
        error "Scoring failed"
        exit 1
    fi
    echo ""

    # ========================================================================
    # COMPLETION SUMMARY
    # ========================================================================
    separator
    success "NVE INFRASTRUCTURE DATA LOADING COMPLETE"
    separator
    log "End time: $(date)"
    echo ""

    # Generate summary statistics
    log "Generating summary report..."
    psql "$DATABASE_URL" -c "
        SELECT
            'Power Lines Loaded' as metric,
            COUNT(*)::text as value
        FROM nve_power_lines
        UNION ALL
        SELECT
            'Power Poles Loaded',
            COUNT(*)::text
        FROM nve_power_poles
        UNION ALL
        SELECT
            'Transformers Loaded',
            COUNT(*)::text
        FROM nve_transformers
        UNION ALL
        SELECT
            'Cabins with Grid Scores',
            COUNT(*)::text
        FROM cabins
        WHERE weak_grid_score IS NOT NULL
        UNION ALL
        SELECT
            'High-Priority Leads (Score ≥90)',
            COUNT(*)::text
        FROM cabins
        WHERE weak_grid_score >= 90
        UNION ALL
        SELECT
            'Good Prospects (Score ≥70)',
            COUNT(*)::text
        FROM cabins
        WHERE weak_grid_score >= 70;
    " | tee -a "$LOG_FILE"

    echo ""
    log "Next steps:"
    echo "  1. Export top leads:"
    echo "     psql \$DATABASE_URL -c \"COPY (SELECT * FROM top_500_weak_grid_leads) TO '/tmp/top_500_leads.csv' CSV HEADER;\""
    echo ""
    echo "  2. Visualize in QGIS:"
    echo "     - Add PostGIS layer: cabins table"
    echo "     - Symbolize by weak_grid_score (graduated colors)"
    echo "     - Add NVE layers: nve_power_lines, nve_power_poles"
    echo ""
    echo "  3. Create postal code aggregates for GDPR compliance:"
    echo "     psql \$DATABASE_URL -c \"SELECT postal_code, COUNT(*), AVG(weak_grid_score) FROM cabins WHERE weak_grid_score >= 70 GROUP BY postal_code;\""
    echo ""

    success "Full log available at: $LOG_FILE"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'error "Pipeline failed at step $BASH_COMMAND"; exit 1' ERR

# ============================================================================
# EXECUTE MAIN PIPELINE
# ============================================================================

main
