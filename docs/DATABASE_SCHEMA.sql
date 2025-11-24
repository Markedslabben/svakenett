-- ============================================================================
-- GRID INFRASTRUCTURE DATABASE SCHEMA
-- ============================================================================
-- Purpose: Store NVE grid infrastructure data and scoring metrics
-- Database: svakenett (PostgreSQL 16 + PostGIS 3.4)
-- Version: 2.0 (Infrastructure-based scoring)
-- ============================================================================

-- ============================================================================
-- 1. GRID INFRASTRUCTURE TABLES
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Power Lines (Distribution Grid)
-- ---------------------------------------------------------------------------
-- Source: NVE Layer 2 - Distribusjonsnett
-- Description: 22kV and higher voltage distribution/transmission lines
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS power_lines (
    id SERIAL PRIMARY KEY,

    -- Geometry
    geometry GEOMETRY(LineString, 4326) NOT NULL,

    -- Line attributes
    voltage_kv INTEGER,                    -- Voltage level (22, 33, 66, 132, etc.)
    line_length_m NUMERIC(10, 2),         -- Line length in meters
    owner_orgnr VARCHAR(20),              -- Grid company organization number
    owner_name VARCHAR(255),              -- Grid company name
    year_built INTEGER,                   -- Year of construction
    line_type VARCHAR(50),                -- Type classification

    -- Metadata
    source_layer VARCHAR(100) DEFAULT 'NVE Distribusjonsnett',
    created_at TIMESTAMP DEFAULT NOW(),

    -- Spatial index
    CONSTRAINT valid_geometry CHECK (ST_IsValid(geometry))
);

-- Spatial index for efficient distance queries
CREATE INDEX IF NOT EXISTS idx_power_lines_geom
    ON power_lines USING GIST(geometry);

-- Index on owner for company lookups
CREATE INDEX IF NOT EXISTS idx_power_lines_owner
    ON power_lines(owner_orgnr);

-- Index on voltage for filtering
CREATE INDEX IF NOT EXISTS idx_power_lines_voltage
    ON power_lines(voltage_kv);

COMMENT ON TABLE power_lines IS 'NVE distribution and transmission grid power lines';
COMMENT ON COLUMN power_lines.voltage_kv IS 'Voltage level in kilovolts (22, 33, 66, 132, etc.)';
COMMENT ON COLUMN power_lines.owner_orgnr IS 'Grid company organization number (eierOrgnr from NVE)';

-- ---------------------------------------------------------------------------
-- Power Poles/Posts
-- ---------------------------------------------------------------------------
-- Source: NVE Layer 4 - Master og stolper
-- Description: Physical poles supporting overhead power lines
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS power_poles (
    id SERIAL PRIMARY KEY,

    -- Geometry
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- Pole attributes
    owner_orgnr VARCHAR(20),              -- Grid company organization number
    owner_name VARCHAR(255),              -- Grid company name
    year_built INTEGER,                   -- Year of installation
    height_m NUMERIC(6, 2),               -- Pole height in meters
    pole_type VARCHAR(50),                -- Type/material classification

    -- Metadata
    source_layer VARCHAR(100) DEFAULT 'NVE Master og stolper',
    created_at TIMESTAMP DEFAULT NOW(),

    -- Spatial index
    CONSTRAINT valid_pole_geometry CHECK (ST_IsValid(geometry))
);

-- Spatial index for location queries
CREATE INDEX IF NOT EXISTS idx_power_poles_geom
    ON power_poles USING GIST(geometry);

-- Index on owner
CREATE INDEX IF NOT EXISTS idx_power_poles_owner
    ON power_poles(owner_orgnr);

COMMENT ON TABLE power_poles IS 'NVE power line poles and posts (overhead infrastructure)';

-- ---------------------------------------------------------------------------
-- Cables (Underground and Sea)
-- ---------------------------------------------------------------------------
-- Source: NVE Layer 3 - Sjøkabler (and underground segments)
-- Description: Underground and submarine power cables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cables (
    id SERIAL PRIMARY KEY,

    -- Geometry
    geometry GEOMETRY(LineString, 4326) NOT NULL,

    -- Cable attributes
    cable_type VARCHAR(50),               -- 'underground', 'sea', etc.
    voltage_kv INTEGER,                   -- Voltage level
    owner_orgnr VARCHAR(20),              -- Grid company organization number
    owner_name VARCHAR(255),              -- Grid company name
    year_built INTEGER,                   -- Year of installation
    cable_length_m NUMERIC(10, 2),        -- Cable length in meters

    -- Metadata
    source_layer VARCHAR(100) DEFAULT 'NVE Sjøkabler',
    created_at TIMESTAMP DEFAULT NOW(),

    -- Spatial index
    CONSTRAINT valid_cable_geometry CHECK (ST_IsValid(geometry))
);

-- Spatial index
CREATE INDEX IF NOT EXISTS idx_cables_geom
    ON cables USING GIST(geometry);

-- Index on type and owner
CREATE INDEX IF NOT EXISTS idx_cables_type
    ON cables(cable_type);
CREATE INDEX IF NOT EXISTS idx_cables_owner
    ON cables(owner_orgnr);

COMMENT ON TABLE cables IS 'NVE underground and sea cables';
COMMENT ON COLUMN cables.cable_type IS 'Cable installation type (underground, sea, etc.)';

-- ---------------------------------------------------------------------------
-- Transformers/Substations
-- ---------------------------------------------------------------------------
-- Source: NVE Layer 5 - Transformatorstasjoner
-- Description: Transformer stations and substations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transformers (
    id SERIAL PRIMARY KEY,

    -- Geometry
    geometry GEOMETRY(Point, 4326) NOT NULL,

    -- Transformer attributes
    owner_orgnr VARCHAR(20),              -- Grid company organization number
    owner_name VARCHAR(255),              -- Grid company name
    year_built INTEGER,                   -- Year of installation
    capacity_kva NUMERIC(10, 2),          -- Capacity in kVA
    voltage_primary_kv INTEGER,           -- Primary voltage level
    voltage_secondary_kv INTEGER,         -- Secondary voltage level
    station_type VARCHAR(50),             -- Type classification

    -- Metadata
    source_layer VARCHAR(100) DEFAULT 'NVE Transformatorstasjoner',
    created_at TIMESTAMP DEFAULT NOW(),

    -- Spatial index
    CONSTRAINT valid_transformer_geometry CHECK (ST_IsValid(geometry))
);

-- Spatial index
CREATE INDEX IF NOT EXISTS idx_transformers_geom
    ON transformers USING GIST(geometry);

-- Index on owner
CREATE INDEX IF NOT EXISTS idx_transformers_owner
    ON transformers(owner_orgnr);

COMMENT ON TABLE transformers IS 'NVE transformer stations and substations';
COMMENT ON COLUMN transformers.capacity_kva IS 'Transformer capacity in kilovolt-amperes';

-- ============================================================================
-- 2. ENHANCED CABINS TABLE
-- ============================================================================

-- Add new columns for grid infrastructure metrics
ALTER TABLE cabins
    -- Distance metrics
    ADD COLUMN IF NOT EXISTS distance_to_line_m NUMERIC(10, 2),
    ADD COLUMN IF NOT EXISTS distance_to_transformer_m NUMERIC(10, 2),

    -- Grid density metrics
    ADD COLUMN IF NOT EXISTS grid_density_lines_1km INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS grid_density_length_km NUMERIC(10, 2),

    -- Grid quality metrics
    ADD COLUMN IF NOT EXISTS grid_age_years NUMERIC(6, 2),
    ADD COLUMN IF NOT EXISTS voltage_level_kv INTEGER,
    ADD COLUMN IF NOT EXISTS nearest_line_owner VARCHAR(20),

    -- Scoring components (0-100 normalized scores)
    ADD COLUMN IF NOT EXISTS score_distance NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS score_density NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS score_kile NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS score_voltage NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS score_age NUMERIC(5, 2),

    -- Final composite score
    ADD COLUMN IF NOT EXISTS weak_grid_score NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS score_category VARCHAR(50),

    -- Metadata
    ADD COLUMN IF NOT EXISTS scoring_updated_at TIMESTAMP;

-- Create indexes on scoring columns for filtering and sorting
CREATE INDEX IF NOT EXISTS idx_cabins_weak_grid_score
    ON cabins(weak_grid_score DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_cabins_score_category
    ON cabins(score_category);

CREATE INDEX IF NOT EXISTS idx_cabins_distance
    ON cabins(distance_to_line_m);

-- Comments
COMMENT ON COLUMN cabins.distance_to_line_m IS 'Distance to nearest power line in meters';
COMMENT ON COLUMN cabins.grid_density_lines_1km IS 'Count of power lines within 1km radius';
COMMENT ON COLUMN cabins.grid_density_length_km IS 'Total length of power lines within 1km (km)';
COMMENT ON COLUMN cabins.grid_age_years IS 'Average age of power lines within 1km radius';
COMMENT ON COLUMN cabins.voltage_level_kv IS 'Voltage level of nearest power line (kV)';
COMMENT ON COLUMN cabins.weak_grid_score IS 'Composite weak grid score (0-100, higher = weaker grid)';
COMMENT ON COLUMN cabins.score_category IS 'Prospect category: Excellent/Good/Moderate/Poor';

-- ============================================================================
-- 3. MATERIALIZED VIEWS FOR PERFORMANCE
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Grid Company Summary with Infrastructure Stats
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS grid_company_infrastructure_stats AS
SELECT
    gc.company_code,
    gc.company_name,
    gc.kile_cost_nok,

    -- Infrastructure counts
    COUNT(DISTINCT pl.id) as power_line_count,
    COUNT(DISTINCT pp.id) as power_pole_count,
    COUNT(DISTINCT c.id) as cable_count,
    COUNT(DISTINCT t.id) as transformer_count,

    -- Total infrastructure length
    COALESCE(SUM(ST_Length(pl.geometry::geography)) / 1000, 0) as total_line_length_km,

    -- Average grid age
    ROUND(AVG(2025 - pl.year_built), 1) as avg_grid_age_years,

    -- Voltage distribution
    COUNT(*) FILTER (WHERE pl.voltage_kv = 22) as lines_22kv,
    COUNT(*) FILTER (WHERE pl.voltage_kv BETWEEN 33 AND 66) as lines_33_66kv,
    COUNT(*) FILTER (WHERE pl.voltage_kv >= 132) as lines_132kv_plus,

    -- Cabin counts
    COUNT(DISTINCT cab.id) as cabin_count,
    AVG(cab.weak_grid_score) as avg_cabin_score

FROM grid_companies gc
LEFT JOIN power_lines pl ON gc.company_code = pl.owner_orgnr
LEFT JOIN power_poles pp ON gc.company_code = pp.owner_orgnr
LEFT JOIN cables c ON gc.company_code = c.owner_orgnr
LEFT JOIN transformers t ON gc.company_code = t.owner_orgnr
LEFT JOIN cabins cab ON gc.company_code = cab.grid_company_code
GROUP BY gc.company_code, gc.company_name, gc.kile_cost_nok;

CREATE UNIQUE INDEX ON grid_company_infrastructure_stats(company_code);

COMMENT ON MATERIALIZED VIEW grid_company_infrastructure_stats IS
    'Summary statistics of grid infrastructure and cabins per grid company';

-- ---------------------------------------------------------------------------
-- High-Value Prospects View
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS high_value_prospects AS
SELECT
    c.id,
    c.geometry,
    c.postal_code,
    c.grid_company_code,
    gc.company_name,
    gc.kile_cost_nok,

    -- Scoring components
    c.distance_to_line_m,
    c.grid_density_lines_1km,
    c.grid_age_years,
    c.voltage_level_kv,
    c.weak_grid_score,
    c.score_category,

    -- Geographic info
    ST_X(c.geometry) as longitude,
    ST_Y(c.geometry) as latitude

FROM cabins c
LEFT JOIN grid_companies gc ON c.grid_company_code = gc.company_code
WHERE c.weak_grid_score >= 70  -- Good or Excellent prospects only
ORDER BY c.weak_grid_score DESC;

CREATE INDEX ON high_value_prospects(weak_grid_score DESC);
CREATE INDEX ON high_value_prospects USING GIST(geometry);

COMMENT ON MATERIALIZED VIEW high_value_prospects IS
    'Cabins with weak grid scores >= 70 (Good or Excellent prospects)';

-- ============================================================================
-- 4. HELPER FUNCTIONS
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Refresh all materialized views
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_grid_analytics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY grid_company_infrastructure_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY high_value_prospects;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_grid_analytics() IS
    'Refresh all grid infrastructure materialized views';

-- ---------------------------------------------------------------------------
-- Calculate weak grid score for a single cabin
-- ---------------------------------------------------------------------------
-- Note: Actual implementation in Python scripts, this is SQL placeholder
CREATE OR REPLACE FUNCTION calculate_weak_grid_score(
    p_distance_m NUMERIC,
    p_density_lines INTEGER,
    p_kile_cost NUMERIC,
    p_voltage_kv INTEGER,
    p_age_years NUMERIC
)
RETURNS NUMERIC AS $$
DECLARE
    v_score_distance NUMERIC;
    v_score_density NUMERIC;
    v_score_kile NUMERIC;
    v_score_voltage NUMERIC;
    v_score_age NUMERIC;
    v_final_score NUMERIC;
BEGIN
    -- Normalize distance (0-100 scale)
    v_score_distance := CASE
        WHEN p_distance_m <= 100 THEN 0
        WHEN p_distance_m <= 500 THEN ((p_distance_m - 100) / 400.0) * 50
        WHEN p_distance_m <= 2000 THEN 50 + ((p_distance_m - 500) / 1500.0) * 40
        ELSE 100
    END;

    -- Normalize density
    v_score_density := CASE
        WHEN p_density_lines >= 10 THEN 0
        WHEN p_density_lines >= 6 THEN 20
        WHEN p_density_lines >= 3 THEN 50
        WHEN p_density_lines >= 1 THEN 80
        ELSE 100
    END;

    -- Normalize KILE
    v_score_kile := CASE
        WHEN p_kile_cost <= 500 THEN 0
        WHEN p_kile_cost <= 1500 THEN ((p_kile_cost - 500) / 1000.0) * 50
        WHEN p_kile_cost <= 3000 THEN 50 + ((p_kile_cost - 1500) / 1500.0) * 30
        ELSE 100
    END;

    -- Normalize voltage
    v_score_voltage := CASE
        WHEN p_voltage_kv >= 132 THEN 0
        WHEN p_voltage_kv >= 33 THEN 50
        ELSE 100
    END;

    -- Normalize age
    v_score_age := CASE
        WHEN p_age_years <= 10 THEN 0
        WHEN p_age_years <= 20 THEN 25
        WHEN p_age_years <= 30 THEN 50
        WHEN p_age_years <= 40 THEN 75
        ELSE 100
    END;

    -- Calculate weighted composite score
    v_final_score := (0.40 * v_score_distance) +
                     (0.25 * v_score_density) +
                     (0.15 * v_score_kile) +
                     (0.10 * v_score_voltage) +
                     (0.10 * v_score_age);

    RETURN ROUND(v_final_score, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_weak_grid_score IS
    'Calculate composite weak grid score from individual metrics (0-100 scale)';

-- ============================================================================
-- 5. DATA QUALITY CHECKS
-- ============================================================================

-- View for monitoring data quality
CREATE OR REPLACE VIEW data_quality_summary AS
SELECT
    'power_lines' as table_name,
    COUNT(*) as total_rows,
    COUNT(*) FILTER (WHERE geometry IS NULL) as null_geometry,
    COUNT(*) FILTER (WHERE voltage_kv IS NULL) as null_voltage,
    COUNT(*) FILTER (WHERE owner_orgnr IS NULL) as null_owner,
    COUNT(*) FILTER (WHERE year_built IS NULL) as null_year
FROM power_lines

UNION ALL

SELECT
    'cabins' as table_name,
    COUNT(*) as total_rows,
    COUNT(*) FILTER (WHERE geometry IS NULL) as null_geometry,
    COUNT(*) FILTER (WHERE weak_grid_score IS NULL) as null_score,
    COUNT(*) FILTER (WHERE distance_to_line_m IS NULL) as null_distance,
    COUNT(*) FILTER (WHERE grid_company_code IS NULL) as null_company
FROM cabins

UNION ALL

SELECT
    'transformers' as table_name,
    COUNT(*) as total_rows,
    COUNT(*) FILTER (WHERE geometry IS NULL) as null_geometry,
    COUNT(*) FILTER (WHERE capacity_kva IS NULL) as null_capacity,
    COUNT(*) FILTER (WHERE owner_orgnr IS NULL) as null_owner,
    NULL as extra_stat
FROM transformers;

COMMENT ON VIEW data_quality_summary IS
    'Data quality monitoring: null counts and completeness checks';

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
