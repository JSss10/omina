// AsyncRetry.swift
// Omina
//
// Kleine Hilfe, um eine asynchrone Operation bei Fehlern begrenzt oft mit
// exponentiellem Backoff zu wiederholen. Fängt am Testtag kurze Funklöcher
// oder Timeouts der Supabase-RPCs ab, ohne die UI lange zu blockieren – der
// Daten-Cache zeigt bereits Inhalte, der Refresh darf also in Ruhe erneut
// versuchen.

import Foundation

/// Führt `operation` aus und wiederholt sie bei einem geworfenen Fehler bis zu
/// `maxAttempts` mal (inkl. Erstversuch), mit sich verdoppelnder Wartezeit ab
/// `initialDelay`. Bricht sofort ab, wenn der Task abgebrochen wurde, und wirft
/// dann den letzten Fehler weiter.
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: Duration = .milliseconds(400),
    operation: () async throws -> T
) async throws -> T {
    var attempt = 1
    var delay = initialDelay
    while true {
        do {
            return try await operation()
        } catch {
            if attempt >= maxAttempts || Task.isCancelled {
                throw error
            }
            try? await Task.sleep(for: delay)
            delay = delay * 2
            attempt += 1
        }
    }
}
