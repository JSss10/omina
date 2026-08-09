-- Omina – Supabase Schema v2.0
-- Stand: 28.03.2026 | Phase 2

CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. barriers
CREATE TABLE barriers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type            VARCHAR(50) NOT NULL,
    subtype         VARCHAR(100),
    value           DECIMAL,
    unit            VARCHAR(20),
    location        GEOGRAPHY(POINT, 4326) NOT NULL,
    location_line   GEOGRAPHY(LINESTRING, 4326),
    value_source    VARCHAR(20) DEFAULT 'measured',
    source          VARCHAR(50) NOT NULL,
    source_id       VARCHAR(255),
    source_tags     JSONB,
    last_verified   TIMESTAMP,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_barriers_location ON barriers USING GIST (location);
CREATE INDEX idx_barriers_type ON barriers (type);
CREATE INDEX idx_barriers_active ON barriers (is_active) WHERE is_active = true;

-- 2. poi_accessibility
CREATE TABLE poi_accessibility (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    category        VARCHAR(100),
    location        GEOGRAPHY(POINT, 4326) NOT NULL,
    address         VARCHAR(500),
    wheelchair_accessible VARCHAR(50),
    accessibility_details JSONB,
    source          VARCHAR(50) NOT NULL,
    source_id       VARCHAR(255),
    last_updated    TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_poi_location ON poi_accessibility USING GIST (location);
CREATE INDEX idx_poi_category ON poi_accessibility (category);

-- 3. test_areas
CREATE TABLE test_areas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    boundary        GEOGRAPHY(POLYGON, 4326) NOT NULL,
    description     TEXT,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 4. user_feedback
CREATE TABLE user_feedback (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    barrier_id      UUID REFERENCES barriers(id),
    user_id         UUID NOT NULL,
    feedback_type   VARCHAR(50) NOT NULL,
    correct_value   DECIMAL,
    comment         TEXT,
    photo_url       TEXT,
    status          VARCHAR(20) DEFAULT 'pending',
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_feedback_barrier ON user_feedback (barrier_id);

-- 5. saved_places
CREATE TABLE saved_places (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    name            VARCHAR(255),
    location        GEOGRAPHY(POINT, 4326) NOT NULL,
    place_type      VARCHAR(50),
    reference_id    UUID,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_saved_user ON saved_places (user_id);

-- 6. Testgebiet einfügen
INSERT INTO test_areas (name, description, boundary) VALUES (
    'Altstadt Zürich Niederdorf/Oberdorf',
    'Primäres Testgebiet. Bounding Box: 47.369,8.539 – 47.375,8.547.',
    ST_GeogFromText('POLYGON((8.539 47.369, 8.547 47.369, 8.547 47.375, 8.539 47.375, 8.539 47.369))')
);

-- 7. Row Level Security
ALTER TABLE barriers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "barriers_read" ON barriers FOR SELECT USING (true);

ALTER TABLE poi_accessibility ENABLE ROW LEVEL SECURITY;
CREATE POLICY "poi_read" ON poi_accessibility FOR SELECT USING (true);

ALTER TABLE user_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "feedback_insert" ON user_feedback FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "feedback_select" ON user_feedback FOR SELECT USING (auth.uid() = user_id);

ALTER TABLE saved_places ENABLE ROW LEVEL SECURITY;
CREATE POLICY "saved_insert" ON saved_places FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "saved_select" ON saved_places FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "saved_delete" ON saved_places FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE test_areas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "test_areas_read" ON test_areas FOR SELECT USING (true);
