/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Supabase-Projekt-URL, z. B. https://xyz.supabase.co */
  readonly VITE_SUPABASE_URL: string;
  /** Öffentlicher anon Key. Niemals den service_role Key hier eintragen –
   *  der Zugriff auf die Testdaten läuft über RLS (siehe
   *  migrations/dashboard_access.sql). */
  readonly VITE_SUPABASE_ANON_KEY: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}