-- Omina – Supabase Schema v2.1
-- Stand: 09.08.2026 | Phase 2

-- PostGIS ins Schema "extensions" statt "public" installieren:
-- verhindert die Supabase-Advisor-Warnung "rls_disabled_in_public"
-- für die Extension-Tabelle spatial_ref_sys. Das Schema "extensions"
-- liegt bei Supabase standardmässig im search_path.
--
-- Achtung: Steckt PostGIS in einem bestehenden Projekt bereits in "public",
-- ist das hier wegen IF NOT EXISTS ein No-Op – die Extension wandert nicht
-- nachträglich um. Dann entweder neu aufsetzen oder die Advisor-Warnung
-- für spatial_ref_sys bewusst stehen lassen.
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

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

-- 8. Explizite Grants für die Data-API-Rollen
-- Seit 30.05.2026 vergibt Supabase für neue Tabellen keine impliziten
-- Grants mehr (ab 30.10.2026 auch für bestehende Projekte). Ohne GRANT
-- liefert PostgREST den Fehler 42501. RLS bleibt trotzdem massgeblich:
-- die Policies aus Abschnitt 7 schränken ein, was die Rollen sehen.

GRANT SELECT ON barriers, poi_accessibility, test_areas
    TO anon, authenticated;

GRANT SELECT, INSERT ON user_feedback TO authenticated;
GRANT SELECT, INSERT, DELETE ON saved_places TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON barriers, poi_accessibility, test_areas, user_feedback, saved_places
    TO service_role;

-- 9. RPC-Funktionen für die App (Umkreissuche)
-- Deckungsgleich mit supabase/migrations/barriers_within_radius.sql und
-- supabase/migrations/pois_within_radius.sql – dort stehen die ausführlichen
-- Kommentare zu Aufruf und Rückgabewerten. Wer das Schema frisch aufsetzt,
-- braucht die beiden Migrationen danach nicht mehr einzeln auszuführen.
--
-- Fixierter search_path (public, extensions, pg_temp) verhindert die
-- Advisor-Warnung "function_search_path_mutable"; extensions wird für
-- PostGIS gebraucht, pg_temp gehört ans Ende der Liste.

CREATE OR REPLACE FUNCTION barriers_within_radius(
    lat double precision,
    lng double precision,
    radius_meters double precision
)
RETURNS TABLE (
    id            uuid,
    type          varchar,
    subtype       varchar,
    value         decimal,
    unit          varchar,
    latitude      double precision,
    longitude     double precision,
    value_source  varchar,
    source        varchar,
    source_id     varchar,
    is_active     boolean,
    last_verified timestamp,
    created_at    timestamp,
    updated_at    timestamp
)
LANGUAGE sql
STABLE
SET search_path = public, extensions, pg_temp
AS $$
    SELECT
        b.id,
        b.type,
        b.subtype,
        b.value,
        b.unit,
        ST_Y(b.location::geometry) AS latitude,
        ST_X(b.location::geometry) AS longitude,
        b.value_source,
        b.source,
        b.source_id,
        b.is_active,
        b.last_verified,
        b.created_at,
        b.updated_at
    FROM public.barriers AS b
    WHERE b.is_active = true
      AND ST_DWithin(
          b.location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
    ORDER BY b.location <-> ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography;
$$;

CREATE OR REPLACE FUNCTION pois_within_radius(
    lat double precision,
    lng double precision,
    radius_meters double precision,
    search text DEFAULT NULL
)
RETURNS TABLE (
    id                    uuid,
    name                  varchar,
    category              varchar,
    latitude              double precision,
    longitude             double precision,
    address               varchar,
    wheelchair_accessible varchar,
    accessibility_details jsonb,
    source                varchar,
    distance_m            double precision
)
LANGUAGE sql
STABLE
SET search_path = public, extensions, pg_temp
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        ST_Y(p.location::geometry)  AS latitude,
        ST_X(p.location::geometry)  AS longitude,
        p.address,
        p.wheelchair_accessible,
        p.accessibility_details,
        p.source,
        ST_Distance(
            p.location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS distance_m
    FROM public.poi_accessibility AS p
    WHERE ST_DWithin(
          p.location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
      AND (
          search IS NULL
          OR p.name ILIKE '%' || search || '%'
          OR p.category ILIKE '%' || search || '%'
      )
    ORDER BY distance_m
    -- Hoch genug für alle POIs der Zürcher Altstadt (ginto-Seed: ~440
    -- Einträge), damit die Karte die ganze Altstadt abdecken kann.
    LIMIT 500;
$$;

GRANT EXECUTE ON FUNCTION
    barriers_within_radius(double precision, double precision, double precision),
    pois_within_radius(double precision, double precision, double precision, text)
    TO anon, authenticated, service_role;
