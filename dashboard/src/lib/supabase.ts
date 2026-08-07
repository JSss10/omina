// supabase.ts
// Supabase-Client des Dashboards.
//
// Verwendet ausschliesslich den öffentlichen anon Key. Wer welche Zeilen
// lesen darf, entscheidet Row Level Security auf der Datenbank
// (migrations/dashboard_access.sql) – nicht der Schlüssel im Browser.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

/**
 * Fehlt die Konfiguration, soll das früh und mit einer Anleitung auffallen –
 * nicht später als undurchsichtiger Netzwerkfehler.
 */
export function missingConfig(): string | null {
  if (!url || url.includes("YOUR_PROJECT")) {
    return "VITE_SUPABASE_URL ist nicht gesetzt. Lege dashboard/.env nach dem Vorbild von .env.example an.";
  }
  if (!anonKey || anonKey.includes("YOUR_ANON")) {
    return "VITE_SUPABASE_ANON_KEY ist nicht gesetzt. Lege dashboard/.env nach dem Vorbild von .env.example an.";
  }
  return null;
}

// `createClient` wirft bei leerer URL bereits beim Laden des Moduls. Ohne
// Platzhalter bliebe die Seite deshalb weiss, statt die Meldung aus
// `missingConfig()` zu zeigen. Angefragt wird der Platzhalter nie: main.ts
// prüft die Konfiguration, bevor die erste Abfrage läuft.
const PLACEHOLDER_URL = "https://placeholder.invalid";
const PLACEHOLDER_KEY = "placeholder";

export const supabase: SupabaseClient = createClient(
  url === undefined || url === "" ? PLACEHOLDER_URL : url,
  anonKey === undefined || anonKey === "" ? PLACEHOLDER_KEY : anonKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
    },
  },
);