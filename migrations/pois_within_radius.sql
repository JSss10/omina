-- Omina – Stored Function für POI-Suche im Radius
-- Erwartet das Schema aus Database/schema.sql (Tabelle poi_accessibility).
--
-- search filtert case-insensitiv über Name UND Kategorie, damit die
-- Kategorie-Chips (Café, WC, …) und die Freitext-Suche dieselbe RPC nutzen.
--
-- Aufruf vom Client:
--   supabase.rpc("pois_within_radius",
--     params: ["lat": 47.372, "lng": 8.543, "radius_meters": 500, "search": "wc"])

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
-- Fixierter search_path (Supabase-Linter: function_search_path_mutable).
-- `extensions` ist enthalten, falls PostGIS dort statt in `public` installiert ist.
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

COMMENT ON FUNCTION pois_within_radius(double precision, double precision, double precision, text)
    IS 'POIs im Radius um (lat,lng), optional gefiltert über Name/Kategorie, sortiert nach Distanz.';