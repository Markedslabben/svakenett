-- ============================================================================
-- NVE Grid Infrastructure Database Schema
-- ============================================================================
-- Purpose: Store Norwegian grid infrastructure data for weak grid identification
-- Source: NVE (Norwegian Water Resources and Energy Directorate) open data
-- Coverage: Agder county (25 municipalities, ~15,000 cabins)
-- Date: 2025-01-22
-- ============================================================================

-- Drop existing tables if they exist (for clean reinstall)
DROP TABLE IF EXISTS nve_transformers CASCADE;
DROP TABLE IF EXISTS nve_power_poles CASCADE;
DROP TABLE IF EXISTS nve_power_lines CASCADE;

-- ============================================================================
-- 1. POWER LINES (Kraftlinje + Sjøkabel combined)
-- ============================================================================
-- Contains both overhead power lines and submarine power cables
-- Primary use: Identify 22kV distribution grid for weak grid scoring
-- ============================================================================

CREATE TABLE nve_power_lines (
    id SERIAL PRIMARY KEY,

    -- ========================================
    -- Geometry (WGS84 for compatibility)
    -- ========================================
    geometry GEOMETRY(MultiLineString, 4326) NOT NULL,

    -- ========================================
    -- Core Attributes
    -- ========================================
    objekt_type VARCHAR(50),                -- EL_Luftlinje (overhead) or EL_Sjøkabel (sea cable)
    nve_nett_nivaa INTEGER,                 -- 1=Transmission, 2=Regional, 3=Distribution
    nett_nivaa_navn VARCHAR(50),            -- Human-readable level name
    spenning_kv REAL,                       -- Voltage level (KEY: 22kV = weak distribution)

    -- ========================================
    -- Ownership & KILE Linkage
    -- ========================================
    eier VARCHAR(100),                      -- Owner name (e.g., "AGDER ENERGI NETT AS")
    eier_org_nr BIGINT,                     -- Organization number (link to grid_companies.company_code)
    navn VARCHAR(100),                      -- Line name/identifier

    -- ========================================
    -- Infrastructure Age & Quality
    -- ========================================
    driftsatt_aar INTEGER,                  -- Year commissioned (1920-2024 range)
    alder_aar INTEGER,                      -- Calculated age: 2025 - driftsatt_aar

    -- ========================================
    -- Spatial Properties
    -- ========================================
    lengde_m REAL,                          -- Line length in meters (ST_Length in UTM)

    -- ========================================
    -- Metadata & Provenance
    -- ========================================
    lokal_id UUID,                          -- Permanent UUID from NVE
    nve_opprettet_dato DATE,                -- Created date in NVE system
    kilde_endret_dato DATE,                 -- Source data last modified
    data_uttaks_dato DATE,                  -- Data extraction date

    -- ========================================
    -- Timestamps
    -- ========================================
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Spatial index for fast geographic queries
CREATE INDEX idx_nve_power_lines_geom ON nve_power_lines USING GIST(geometry);

-- Attribute indexes for filtering
CREATE INDEX idx_nve_power_lines_voltage ON nve_power_lines(spenning_kv);
CREATE INDEX idx_nve_power_lines_level ON nve_power_lines(nve_nett_nivaa);
CREATE INDEX idx_nve_power_lines_owner ON nve_power_lines(eier_org_nr);
CREATE INDEX idx_nve_power_lines_lokal_id ON nve_power_lines(lokal_id);

-- Composite index for weak grid queries (Level 3 + 22kV)
CREATE INDEX idx_nve_power_lines_weak_grid ON nve_power_lines(nve_nett_nivaa, spenning_kv)
    WHERE nve_nett_nivaa = 3 AND spenning_kv = 22.0;

-- Comment for documentation
COMMENT ON TABLE nve_power_lines IS 'NVE power transmission infrastructure (overhead lines + submarine cables). Primary use: 22kV distribution grid identification for weak grid scoring.';
COMMENT ON COLUMN nve_power_lines.nve_nett_nivaa IS '1=Transmission (132-420kV), 2=Regional (33-66kV), 3=Distribution (22-24kV)';
COMMENT ON COLUMN nve_power_lines.spenning_kv IS 'Voltage level in kV. 22kV = typical weak distribution grid.';
COMMENT ON COLUMN nve_power_lines.eier_org_nr IS 'Links to grid_companies.company_code for KILE cost analysis';


-- ============================================================================
-- 2. POWER POLES (Mast)
-- ============================================================================
-- Point features representing physical poles/towers supporting power lines
-- Primary use: Density analysis for grid infrastructure maturity
-- ============================================================================

CREATE TABLE nve_power_poles (
    id SERIAL PRIMARY KEY,

    -- ========================================
    -- Geometry (WGS84)
    -- ========================================
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- ========================================
    -- Core Attributes
    -- ========================================
    objekt_type VARCHAR(50),                -- EL_Mast
    nve_nett_nivaa INTEGER,                 -- Grid level (1-3)
    nett_nivaa_navn VARCHAR(50),            -- Level name

    -- ========================================
    -- Ownership
    -- ========================================
    eier VARCHAR(100),                      -- Owner name
    eier_org_nr BIGINT,                     -- Organization number

    -- ========================================
    -- Infrastructure Details
    -- ========================================
    driftsatt_aar INTEGER,                  -- Year commissioned
    alder_aar INTEGER,                      -- Calculated age
    maste_hoyde_m REAL,                     -- Pole height in meters

    -- ========================================
    -- Metadata
    -- ========================================
    lokal_id UUID,                          -- Permanent UUID
    nve_opprettet_dato DATE,
    kilde_endret_dato DATE,

    -- ========================================
    -- Timestamps
    -- ========================================
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Spatial index
CREATE INDEX idx_nve_power_poles_geom ON nve_power_poles USING GIST(geometry);

-- Attribute indexes
CREATE INDEX idx_nve_power_poles_level ON nve_power_poles(nve_nett_nivaa);
CREATE INDEX idx_nve_power_poles_owner ON nve_power_poles(eier_org_nr);

-- Distribution poles filter (most common)
CREATE INDEX idx_nve_power_poles_distribution ON nve_power_poles(nve_nett_nivaa)
    WHERE nve_nett_nivaa = 3;

COMMENT ON TABLE nve_power_poles IS 'Physical power poles/towers. Used for grid density analysis.';


-- ============================================================================
-- 3. TRANSFORMER STATIONS (Transformatorstasjon)
-- ============================================================================
-- Step-down transformers converting higher voltage to distribution voltage
-- Primary use: Grid supply point identification and capacity assessment
-- ============================================================================

CREATE TABLE nve_transformers (
    id SERIAL PRIMARY KEY,

    -- ========================================
    -- Geometry (WGS84)
    -- ========================================
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- ========================================
    -- Core Attributes
    -- ========================================
    objekt_type VARCHAR(50),                -- EL_Transformatorstasjon
    nve_nett_nivaa INTEGER,                 -- Grid level
    nett_nivaa_navn VARCHAR(50),
    spenning_kv REAL,                       -- Input voltage

    -- ========================================
    -- Identification
    -- ========================================
    eier VARCHAR(100),
    eier_org_nr BIGINT,
    navn VARCHAR(100),                      -- Station name
    driftsatt_aar INTEGER,

    -- ========================================
    -- Metadata
    -- ========================================
    lokal_id UUID,
    nve_opprettet_dato DATE,
    kilde_endret_dato DATE,

    -- ========================================
    -- Timestamps
    -- ========================================
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Spatial index
CREATE INDEX idx_nve_transformers_geom ON nve_transformers USING GIST(geometry);

-- Attribute indexes
CREATE INDEX idx_nve_transformers_level ON nve_transformers(nve_nett_nivaa);

COMMENT ON TABLE nve_transformers IS 'Transformer stations. Used to calculate distance from power source.';


-- ============================================================================
-- 4. EXTEND CABINS TABLE WITH GRID ATTRIBUTES
-- ============================================================================
-- Add columns to existing cabins table for grid infrastructure analysis
-- ============================================================================

-- Add grid-related columns to cabins table
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS distance_to_line_m REAL;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS nearest_line_id INTEGER
    REFERENCES nve_power_lines(id);
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS nearest_line_voltage_kv REAL;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS nearest_line_age_years INTEGER;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS grid_density_1km INTEGER;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS grid_line_length_1km_m REAL;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS nearest_transformer_m REAL;
ALTER TABLE cabins ADD COLUMN IF NOT EXISTS weak_grid_score REAL;

-- Indexes for cabin scoring queries
CREATE INDEX IF NOT EXISTS idx_cabins_distance_to_line ON cabins(distance_to_line_m);
CREATE INDEX IF NOT EXISTS idx_cabins_weak_grid_score ON cabins(weak_grid_score);
CREATE INDEX IF NOT EXISTS idx_cabins_grid_density ON cabins(grid_density_1km);

-- High-priority prospects filter (score >= 70)
CREATE INDEX IF NOT EXISTS idx_cabins_high_priority ON cabins(weak_grid_score DESC)
    WHERE weak_grid_score >= 70;

COMMENT ON COLUMN cabins.distance_to_line_m IS 'Distance in meters to nearest distribution power line (22kV)';
COMMENT ON COLUMN cabins.grid_density_1km IS 'Number of power lines within 1km radius';
COMMENT ON COLUMN cabins.weak_grid_score IS 'Composite weak grid score (0-100). Higher = weaker grid = better prospect.';


-- ============================================================================
-- 5. SUMMARY STATISTICS VIEW
-- ============================================================================
-- Convenient view for monitoring data quality and coverage
-- ============================================================================

CREATE OR REPLACE VIEW nve_infrastructure_summary AS
SELECT
    'Power Lines' as infrastructure_type,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE nve_nett_nivaa = 3) as distribution_count,
    COUNT(*) FILTER (WHERE spenning_kv = 22.0) as voltage_22kv_count,
    ROUND(AVG(alder_aar), 1) as avg_age_years,
    MIN(driftsatt_aar) as oldest_year,
    MAX(driftsatt_aar) as newest_year
FROM nve_power_lines

UNION ALL

SELECT
    'Power Poles',
    COUNT(*),
    COUNT(*) FILTER (WHERE nve_nett_nivaa = 3),
    NULL,
    ROUND(AVG(alder_aar), 1),
    MIN(driftsatt_aar),
    MAX(driftsatt_aar)
FROM nve_power_poles

UNION ALL

SELECT
    'Transformers',
    COUNT(*),
    COUNT(*) FILTER (WHERE nve_nett_nivaa = 2),  -- Regional transformers
    NULL,
    NULL,
    MIN(driftsatt_aar),
    MAX(driftsatt_aar)
FROM nve_transformers;

COMMENT ON VIEW nve_infrastructure_summary IS 'Summary statistics for loaded NVE infrastructure data';


-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✓ NVE infrastructure schema created successfully';
    RAISE NOTICE '  - nve_power_lines table (with spatial indexes)';
    RAISE NOTICE '  - nve_power_poles table';
    RAISE NOTICE '  - nve_transformers table';
    RAISE NOTICE '  - cabins table extended with grid attributes';
    RAISE NOTICE '  - Summary view created: nve_infrastructure_summary';
END $$;
