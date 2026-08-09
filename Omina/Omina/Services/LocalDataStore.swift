// LocalDataStore.swift
// Omina
//
// Schlanker Datei-Cache für die statischen Altstadt-Daten (Barrieren, POIs).
// Zweck am Testtag:
//   • Schnelle Ladezeit – die Karte zeigt beim App-Start sofort die zuletzt
//     erfolgreich geladenen Daten an, während der Netz-Refresh im Hintergrund
//     läuft.
//   • Keine Unterbrechung – bei kurzen Funklöchern in den engen Gassen bleibt
//     die App mit den letzten Daten bedienbar.
//
// Best-effort: Jeder Lese-/Schreibfehler wird verschluckt; der Netz-Abruf
// bleibt die Quelle der Wahrheit. Encodieren und Decodieren nutzen dieselbe
// ISO-8601-Datumsstrategie, damit `Date`-Felder (z. B. Barrier.lastVerified)
// sauber roundtrippen – unabhängig davon, wie Supabase sie liefert.

import Foundation

enum LocalDataStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static var directory: URL? {
        guard let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("omina-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(_ name: String) -> URL? {
        directory?.appendingPathComponent("\(name).json")
    }

    /// Lädt gecachte Daten oder `nil`, wenn noch kein Cache existiert bzw. der
    /// Inhalt nicht (mehr) zum Modell passt.
    static func load<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        guard let url = fileURL(name),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Speichert den letzten erfolgreichen Netz-Abruf für den nächsten Start.
    static func save<T: Encodable>(_ value: T, named name: String) {
        guard let url = fileURL(name),
              let data = try? encoder.encode(value)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
