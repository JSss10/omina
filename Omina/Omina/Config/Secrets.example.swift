// Secrets.example.swift
// Omina
//
// Template für Secrets.swift.
//
// Setup:
//   1. Diese Datei nach Secrets.swift kopieren (gleicher Ordner).
//   2. Echte Werte einsetzen.
//   3. Secrets.swift NICHT committen (ist via .gitignore ausgeschlossen).
//
// Der #if false-Block sorgt dafür, dass die Vorlage nicht kompiliert wird,
// während die echte Secrets.swift im selben Ordner gebaut wird.

import Foundation

#if false

enum Secrets {
    // Supabase – aus dem Project Dashboard:
    // https://app.supabase.com/project/<id>/settings/api
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_ANON_KEY"

    // ginto Guide API – Bearer-Token aus dem Partner-Account.
    static let gintoAPIKey = "YOUR_GINTO_BEARER_TOKEN"

    // OpenRouteService – kostenloser API-Key für das Rollstuhl-Routing:
    // https://openrouteservice.org/dev/#/signup
    // Leer lassen ist möglich: dann fällt die Navigation auf die
    // MapKit-Fussgängerroute zurück (ohne Barrieren-Berücksichtigung).
    static let openRouteServiceAPIKey = "YOUR_ORS_API_KEY"

    // Hinweis: Das Wetter auf dem Homescreen nutzt Open-Meteo und braucht
    // keinen API-Key.
}

#endif