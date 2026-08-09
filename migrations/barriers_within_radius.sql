-- Omina – Stored Function für Map-Radius-Query
-- Erwartet das Schema aus Database/schema.sql (Spalte `location` GEOGRAPHY(POINT, 4326)).
--
-- Aufruf vom Client (Supabase RPC):
--   supabase.rpc("barriers_within_radius", params: ["lat": 47.372, "lng": 8.543, "radius_meters": 500])
--
-- Hinweis: liefert lat/lng explizit als double precision, weil PostgREST `geography`
-- per Default als WKB-Hex serialisiert und das im iOS-Client unhandlich wäre.

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
-- Fixierter search_path (Supabase-Linter: function_search_path_mutable).
-- `extensions` ist enthalten, falls PostGIS dort statt in `public` installiert ist.
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

COMMENT ON FUNCTION barriers_within_radius(double precision, double precision, double precision)
    IS 'Liefert aktive Barrieren innerhalb von radius_meters um (lat,lng), sortiert nach Distanz, mit explizitem lat/lng.';