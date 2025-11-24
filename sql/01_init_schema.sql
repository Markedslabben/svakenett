-- ============================================================================
-- Svake Nett Analyse - Database Schema
-- PostgreSQL + PostGIS database schema for weak grid customer identification
-- ============================================================================

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- 1. Grid Companies Table (KILE statistics)
-- ============================================================================
CREATE TABLE grid_companies (
    id SERIAL PRIMARY KEY,
    company_name VARCHAR(200) NOT NULL,
    company_code VARCHAR(50) UNIQUE,
    saidi_hours REAL,              -- System Average Interruption Duration Index
    saifi_count REAL,              -- System Average Interruption Frequency Index
    kile_cost_nok REAL,            -- Total KILE compensation paid
    service_area_polygon GEOMETRY(MultiPolygon, 4326),
    data_year INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_grid_companies_geom ON grid_companies USING GIST(service_area_polygon);
CREATE INDEX idx_grid_companies_code ON grid_companies(company_code);

-- ============================================================================
-- 2. Municipalities Table
-- ============================================================================
CREATE TABLE municipalities (
    id SERIAL PRIMARY KEY,
    municipality_number VARCHAR(4) NOT NULL UNIQUE,
    municipality_name VARCHAR(100) NOT NULL,
    county_name VARCHAR(100),
    geometry GEOMETRY(MultiPolygon, 4326),
    population INTEGER,
    area_km2 REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_municipalities_geom ON municipalities USING GIST(geometry);
CREATE INDEX idx_municipalities_number ON municipalities(municipality_number);

-- ============================================================================
-- 3. Postal Codes Table
-- ============================================================================
CREATE TABLE postal_codes (
    id SERIAL PRIMARY KEY,
    postal_code VARCHAR(4) NOT NULL UNIQUE,
    postal_name VARCHAR(100),
    municipality_number VARCHAR(4),
    geometry GEOMETRY(MultiPolygon, 4326),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (municipality_number) REFERENCES municipalities(municipality_number)
);

CREATE INDEX idx_postal_codes_geom ON postal_codes USING GIST(geometry);
CREATE INDEX idx_postal_codes_code ON postal_codes(postal_code);

-- ============================================================================
-- 4. Cabins Table (Main scoring table)
-- ============================================================================
CREATE TABLE cabins (
    id SERIAL PRIMARY KEY,

    -- Geometry and location
    geometry GEOMETRY(Point, 4326) NOT NULL,
    postal_code VARCHAR(4),
    municipality_number VARCHAR(4),

    -- Building metadata (from Kartverket N50)
    building_type VARCHAR(50),
    building_year INTEGER,
    floor_area_m2 REAL,

    -- Calculated features
    distance_to_town_km REAL,
    terrain_elevation_m REAL,
    slope_degrees REAL,

    -- Grid company association
    grid_company_code VARCHAR(50),

    -- KILE statistics (from grid company)
    saidi_hours REAL,
    saifi_count REAL,

    -- Weak grid scores (0-100 scale)
    score_conservative REAL,    -- High confidence threshold
    score_balanced REAL,         -- Recommended default
    score_aggressive REAL,       -- Maximum reach

    -- Metadata
    data_source VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Foreign keys
    FOREIGN KEY (postal_code) REFERENCES postal_codes(postal_code),
    FOREIGN KEY (municipality_number) REFERENCES municipalities(municipality_number),
    FOREIGN KEY (grid_company_code) REFERENCES grid_companies(company_code)
);

-- Spatial index for fast geospatial queries (critical for performance)
CREATE INDEX idx_cabins_geom ON cabins USING GIST(geometry);

-- B-tree indexes for common queries
CREATE INDEX idx_cabins_postal ON cabins(postal_code);
CREATE INDEX idx_cabins_municipality ON cabins(municipality_number);
CREATE INDEX idx_cabins_grid_company ON cabins(grid_company_code);
CREATE INDEX idx_cabins_score_balanced ON cabins(score_balanced DESC);

-- Composite index for filtered geographic queries
CREATE INDEX idx_cabins_score_geom ON cabins(score_balanced DESC, geometry);

-- ============================================================================
-- 5. Aggregated Postal Code Scores (GDPR-compliant output)
-- ============================================================================
CREATE TABLE postal_code_scores (
    id SERIAL PRIMARY KEY,
    postal_code VARCHAR(4) NOT NULL,

    -- Aggregated statistics
    cabin_count INTEGER NOT NULL,
    avg_score_conservative REAL,
    avg_score_balanced REAL,
    avg_score_aggressive REAL,

    -- Grid quality indicators
    avg_saidi_hours REAL,
    avg_saifi_count REAL,
    avg_distance_to_town_km REAL,

    -- Targeting recommendation
    priority_tier VARCHAR(20),    -- 'high', 'medium', 'low'

    -- Metadata
    calculation_date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (postal_code) REFERENCES postal_codes(postal_code),

    -- Ensure minimum count for privacy (GDPR)
    CONSTRAINT min_cabin_count CHECK (cabin_count >= 5)
);

CREATE INDEX idx_postal_scores_code ON postal_code_scores(postal_code);
CREATE INDEX idx_postal_scores_priority ON postal_code_scores(priority_tier, avg_score_balanced DESC);

-- ============================================================================
-- 6. Analysis Metadata Table (track data processing runs)
-- ============================================================================
CREATE TABLE analysis_runs (
    id SERIAL PRIMARY KEY,
    run_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_sources_used JSONB,      -- Track which data sources were used
    total_cabins_processed INTEGER,
    scoring_parameters JSONB,     -- Store scoring weights and thresholds
    validation_metrics JSONB,     -- R-squared, correlations, etc.
    notes TEXT
);

-- ============================================================================
-- 7. Create materialized view for fast dashboard queries
-- ============================================================================
CREATE MATERIALIZED VIEW mv_cabin_summary AS
SELECT
    pc.postal_code,
    pc.postal_name,
    m.municipality_name,
    COUNT(c.id) as cabin_count,
    AVG(c.score_balanced) as avg_score,
    AVG(c.saidi_hours) as avg_saidi,
    AVG(c.distance_to_town_km) as avg_distance,
    ST_Centroid(ST_Collect(c.geometry)) as center_point
FROM cabins c
JOIN postal_codes pc ON c.postal_code = pc.postal_code
JOIN municipalities m ON c.municipality_number = m.municipality_number
WHERE c.score_balanced IS NOT NULL
GROUP BY pc.postal_code, pc.postal_name, m.municipality_name
HAVING COUNT(c.id) >= 5;  -- GDPR: minimum 5 cabins per postal code

CREATE INDEX idx_mv_cabin_summary_score ON mv_cabin_summary(avg_score DESC);
CREATE INDEX idx_mv_cabin_summary_geom ON mv_cabin_summary USING GIST(center_point);

-- ============================================================================
-- 8. Helper Functions
-- ============================================================================

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION refresh_cabin_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_cabin_summary;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate distance to nearest town (placeholder - will be replaced with actual town data)
CREATE OR REPLACE FUNCTION calculate_distance_to_town(cabin_geom GEOMETRY)
RETURNS REAL AS $$
DECLARE
    distance_km REAL;
BEGIN
    -- Placeholder: returns NULL until towns table is populated
    -- Will be updated in Phase 2 with actual town locations
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 9. Grants (adjust as needed for production)
-- ============================================================================
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO svakenett_app;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO svakenett_app;

-- ============================================================================
-- Initial setup complete
-- ============================================================================
COMMENT ON DATABASE svakenett IS 'Svake Nett Analyse - Weak grid customer identification for Norsk Solkraft';
