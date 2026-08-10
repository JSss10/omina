-- dashboard_access.sql
-- Lesezugriff für das Auswertungs-Dashboard (dashboard/).
--
-- Ausgangslage: field_test_tables.sql schützt `test_participants` und
-- `test_events` mit Row Level Security so, dass jede Testperson ausschliesslich
-- ihre eigenen Zeilen sieht (auth.uid() = user_id). Für die Auswertung braucht
-- es genau eine weitere Rolle: die Forschende, die alle Zeilen lesen darf –
-- lesend, nie schreibend.
--
-- Warum nicht einfach der service_role Key im Dashboard? Weil das Dashboard im
-- Browser läuft. Alles, was dort im Bundle landet, ist öffentlich; ein
-- service_role Key würde RLS komplett aushebeln und die Daten der Testpersonen
-- für jede Person mit Zugriff auf die Seite freigeben. Das Dashboard benutzt
-- deshalb den öffentlichen anon Key und meldet sich mit einem echten Konto an –
-- die Berechtigung hängt an der User-ID, nicht am Schlüssel.
--
-- SETUP:
--   1. Dieses Skript im Supabase SQL-Editor ausführen.
--   2. Eigenes Konto anlegen (Dashboard → Authentication → Users → Add user,
--      E-Mail + Passwort) und die User-ID kopieren.
--   3. Ganz unten den INSERT mit dieser ID ausführen.

-- 1. Wer darf auswerten? Eine Zeile pro berechtigtem Konto.
CREATE TABLE IF NOT EXISTS dashboard_researchers (
    user_id     UUID PRIMARY KEY,
    email       VARCHAR(255),
    note        VARCHAR(255),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Prüffunktion für die Policies.
--    SECURITY DEFINER, damit die Abfrage auf dashboard_researchers nicht
--    ihrerseits durch die RLS derselben Tabelle läuft (das ergäbe eine
--    Endlosschleife). Das feste search_path verhindert, dass eine
--    gleichnamige Tabelle in einem anderen Schema untergeschoben wird.
CREATE OR REPLACE FUNCTION is_dashboard_researcher()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM dashboard_researchers WHERE user_id = auth.uid()
    );
$$;

-- 3. Die Tabelle selbst ist ebenfalls geschützt: ein Konto sieht nur den
--    eigenen Eintrag. Eingetragen wird ausschliesslich im SQL-Editor.
ALTER TABLE dashboard_researchers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "researchers_select_own" ON dashboard_researchers;
CREATE POLICY "researchers_select_own" ON dashboard_researchers
    FOR SELECT USING (auth.uid() = user_id);

-- 4. Lesezugriff auf die Feldtestdaten. Die bestehenden Policies aus
--    field_test_tables.sql bleiben unverändert – PostgreSQL verknüpft
--    mehrere PERMISSIVE Policies mit ODR, eine Testperson sieht also
--    weiterhin ihre eigenen Zeilen und sonst nichts.
DROP POLICY IF EXISTS "test_participants_select_researcher" ON test_participants;
CREATE POLICY "test_participants_select_researcher" ON test_participants
    FOR SELECT USING (is_dashboard_researcher());

DROP POLICY IF EXISTS "test_events_select_researcher" ON test_events;
CREATE POLICY "test_events_select_researcher" ON test_events
    FOR SELECT USING (is_dashboard_researcher());

-- Bewusst KEINE INSERT/UPDATE/DELETE-Policy für Forschende: das Dashboard
-- wertet aus, es verändert die Rohdaten des Feldtests nicht.

-- 5. Testtage als eigener Endpunkt.
--    Das Dashboard braucht beim Start nur die Liste der Testtage für das
--    Auswahlfeld – ohne diese Funktion müsste es dafür alle Zeilen laden.
--    SECURITY INVOKER (Standard): die Funktion rechnet mit den Rechten der
--    aufrufenden Person, die RLS oben greift also auch hier.
CREATE OR REPLACE FUNCTION field_test_days()
RETURNS TABLE (
    test_day          DATE,
    participant_count BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT p.test_day, COUNT(*) AS participant_count
    FROM test_participants p
    GROUP BY p.test_day
    ORDER BY p.test_day DESC;
$$;

-- 6. Berechtigung eintragen (User-ID aus Authentication → Users einsetzen):
--
-- INSERT INTO dashboard_researchers (user_id, email, note)
-- VALUES ('00000000-0000-0000-0000-000000000000', 'name@example.com', 'Auswertung Bachelorarbeit')
-- ON CONFLICT (user_id) DO NOTHING;