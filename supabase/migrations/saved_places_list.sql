-- Omina – Stored Function für gespeicherte Orte des Users
-- Erwartet das Schema aus Database/schema.sql (Tabelle saved_places, RLS user-owned).
--
-- Aufruf vom Client (Supabase RPC):
--   supabase.rpc("saved_places_list")
--
-- Hinweis: liefert lat/lng explizit als double precision, weil PostgREST `geography`
-- per Default als WKB-Hex serialisiert und das im iOS-Client unhandlich wäre.
-- SECURITY INVOKER (Default) + Filter auf auth.uid(), damit nur eigene Orte kommen.

CREATE OR REPLACE FUNCTION saved_places_list()
RETURNS TABLE (
    id           uuid,
    name         varchar,
    latitude     double precision,
    longitude    double precision,
    place_type   varchar,
    reference_id uuid,
    created_at   timestamp
)
LANGUAGE sql
STABLE
-- Fixierter search_path (Supabase-Linter: function_search_path_mutable).
SET search_path = public, extensions, pg_temp
AS $$
    SELECT
        sp.id,
        sp.name,
        ST_Y(sp.location::geometry) AS latitude,
        ST_X(sp.location::geometry) AS longitude,
        sp.place_type,
        sp.reference_id,
        sp.created_at
    FROM public.saved_places AS sp
    WHERE sp.user_id = auth.uid()
    ORDER BY sp.created_at DESC;
$$;

COMMENT ON FUNCTION saved_places_list()
    IS 'Liefert die gespeicherten Orte des angemeldeten Users (neueste zuerst) mit explizitem lat/lng.';