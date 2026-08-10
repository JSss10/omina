// data.ts
// Datenzugriff auf die Feldtest-Tabellen über PostgREST (Supabase).
//
// Alle Abfragen laufen mit dem angemeldeten Konto; welche Zeilen zurückkommen,
// entscheidet Row Level Security (supabase/migrations/dashboard_access.sql). Das
// Dashboard filtert also nicht aus Sicherheitsgründen, sondern nur, um weniger
// Daten zu übertragen.

import { supabase } from "./supabase.ts";
import type { EventRow, ParticipantRow, TestDayRow } from "./types.ts";

/** PostgREST liefert pro Anfrage höchstens 1000 Zeilen. */
const PAGE_SIZE = 1000;

/** Die Testtage für das Auswahlfeld (RPC `field_test_days`). */
export async function loadTestDays(): Promise<TestDayRow[]> {
  const { data, error } = await supabase.rpc("field_test_days");
  if (error) throw new Error(`Testtage konnten nicht geladen werden: ${error.message}`);
  return (data ?? []) as TestDayRow[];
}

/** Testpersonen, optional auf einen Testtag eingegrenzt. */
export async function loadParticipants(
  testDay: string | null,
): Promise<ParticipantRow[]> {
  let query = supabase
    .from("test_participants")
    .select("*")
    .order("created_at", { ascending: true });

  if (testDay !== null) {
    query = query.eq("test_day", testDay);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(`Testpersonen konnten nicht geladen werden: ${error.message}`);
  }
  return (data ?? []) as ParticipantRow[];
}

/**
 * Ereignisse der angegebenen Testpersonen.
 *
 * `test_events` hat keine Testtag-Spalte – die Zuordnung läuft über die
 * `user_id` der Testpersonen. Geladen wird seitenweise, weil ein Testtag
 * die 1000-Zeilen-Grenze von PostgREST überschreiten kann.
 */
export async function loadEvents(
  userIds: readonly string[],
): Promise<EventRow[]> {
  if (userIds.length === 0) return [];

  const rows: EventRow[] = [];
  for (let page = 0; ; page += 1) {
    const from = page * PAGE_SIZE;
    const { data, error } = await supabase
      .from("test_events")
      .select("*")
      .in("user_id", [...userIds])
      .order("occurred_at", { ascending: true })
      .range(from, from + PAGE_SIZE - 1);

    if (error) {
      throw new Error(`Ereignisse konnten nicht geladen werden: ${error.message}`);
    }

    const batch = (data ?? []) as EventRow[];
    rows.push(...batch);

    if (batch.length < PAGE_SIZE) break;
  }
  return rows;
}

/**
 * Prüft, ob das angemeldete Konto für die Auswertung freigeschaltet ist.
 *
 * Ohne Freischaltung greift die RLS und alle Abfragen kommen leer zurück –
 * das sähe aus wie «keine Daten» statt wie «kein Zugriff». Diese Abfrage
 * unterscheidet die beiden Fälle.
 */
export async function isResearcher(): Promise<boolean> {
  const { data, error } = await supabase
    .from("dashboard_researchers")
    .select("user_id")
    .limit(1);

  if (error) return false;
  return (data ?? []).length > 0;
}