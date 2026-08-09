-- field_test_tables.sql
-- Feldtest Altstadt Zürich (3 Testtage): Tabellen für Testpersonen und
-- Interaktions-Tracking, getrennt von den regulären App-Tabellen.
--
-- SETUP (einmalig, vor dem ersten Testtag):
--   1. Dieses Skript im Supabase SQL-Editor ausführen.
--   2. Supabase Dashboard → Authentication → Sign In / Providers →
--      "Allow anonymous sign-ins" AKTIVIEREN.
--      (Die Testpersonen melden sich nicht mit E-Mail an, sondern bekommen
--      beim Auswählen ihres Testprofils automatisch einen anonymen User.)
--
-- AUSWERTUNG: siehe View `test_event_overview` ganz unten – im SQL-Editor
--   z. B.  SELECT * FROM test_event_overview WHERE test_day = '2026-07-21';

-- 1. Testpersonen: eine Zeile pro Testperson (= pro gewähltem Testprofil
--    auf einem Gerät). `profile` enthält die Onboarding-Antworten als JSON.
CREATE TABLE IF NOT EXISTS test_participants (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL UNIQUE,          -- anonyme Auth-User-ID
    test_profile_key  VARCHAR(30) NOT NULL,          -- z. B. 'tp03'
    display_name      VARCHAR(120) NOT NULL,         -- Name des Testprofils
    test_day          DATE NOT NULL DEFAULT CURRENT_DATE,
    profile           JSONB,                         -- Onboarding-Daten (UserProfile)
    device_model      VARCHAR(80),
    app_version       VARCHAR(40),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_test_participants_day ON test_participants (test_day);
CREATE INDEX IF NOT EXISTS idx_test_participants_key ON test_participants (test_profile_key);

-- 2. Interaktions-Events: jeder Klick / Screen-Aufruf, den die App trackt.
CREATE TABLE IF NOT EXISTS test_events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL,                 -- gleiche ID wie test_participants.user_id
    test_profile_key  VARCHAR(30) NOT NULL,
    session_id        UUID NOT NULL,                 -- pro Testlauf konstant
    event_name        VARCHAR(100) NOT NULL,         -- z. B. 'screen_view', 'route_started'
    screen            VARCHAR(100),                  -- z. B. 'poi_detail'
    properties        JSONB,                         -- Zusatzinfos, z. B. {"poi": "Café Schober"}
    occurred_at       TIMESTAMPTZ NOT NULL,          -- Zeitpunkt auf dem Gerät
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_test_events_user ON test_events (user_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_test_events_name ON test_events (event_name);

-- 3. Row Level Security: Testpersonen (anonyme User) dürfen nur ihre
--    eigenen Zeilen schreiben/lesen. Die Auswertung machst du im Dashboard
--    (service_role umgeht RLS).
ALTER TABLE test_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "test_participants_insert" ON test_participants
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "test_participants_update" ON test_participants
    FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "test_participants_select" ON test_participants
    FOR SELECT USING (auth.uid() = user_id);

ALTER TABLE test_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "test_events_insert" ON test_events
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "test_events_select" ON test_events
    FOR SELECT USING (auth.uid() = user_id);

-- 4. Auswertungs-View: alle Events mit Namen der Testperson verknüpft.
--    security_invoker = true, damit die View die RLS der Tabellen respektiert
--    (im Dashboard mit service_role siehst du trotzdem alles).
CREATE OR REPLACE VIEW test_event_overview
WITH (security_invoker = true) AS
SELECT
    p.display_name,
    p.test_profile_key,
    p.test_day,
    e.session_id,
    e.event_name,
    e.screen,
    e.properties,
    e.occurred_at
FROM test_events e
JOIN test_participants p USING (user_id)
ORDER BY e.occurred_at;