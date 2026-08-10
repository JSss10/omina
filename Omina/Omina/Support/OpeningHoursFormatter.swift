// OpeningHoursFormatter.swift
// Omina
//
// Öffnungszeiten immer auf Deutsch und immer in derselben Form – eine Zeile
// je Wochentag: «Mo: 08:00 – 12:00 Uhr».
//
// Die Rohdaten kommen aus dem Open-Data-API von Zürich Tourismus und tragen
// englische Tageskürzel («Mo,Tu,We,Th,Fr 13:00:00-22:00:00») bzw. liegen
// strukturiert als opening_hours_spec vor (Tage 1 = Montag … 7 = Sonntag).
// Beide Formen landen hier und kommen als deutsche Zeilen wieder heraus.

import Foundation

// `nonisolated`, weil das Projekt mit MainActor als Standard-Isolation baut
// (SWIFT_DEFAULT_ACTOR_ISOLATION), das Aufbereiten der Zeiten aber reine
// Rechnerei auf Zeichenketten ist – ohne Zustand und ohne UI. Aufgerufen wird
// sie unter anderem aus POI, das auch abseits des Hauptthreads dekodiert wird.
nonisolated enum OpeningHoursFormatter {

    /// Ein Zeitfenster an einem Wochentag (1 = Montag … 7 = Sonntag).
    struct Window {
        let day: Int
        let opens: String
        let closes: String
    }

    /// Deutsche Kürzel, Montag zuerst.
    static let weekdayAbbreviations = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    // MARK: - Ausgabe

    /// Eine Zeile je Wochentag, in Wochenreihenfolge. Tage ohne Zeitfenster
    /// (geschlossen) tauchen nicht auf, mehrere Fenster am selben Tag stehen
    /// in einer Zeile: «Mo: 11:30 – 14:30, 18:00 – 23:00 Uhr».
    static func lines(from windows: [Window]) -> [String] {
        var rangesByDay: [Int: [String]] = [:]

        for window in windows where (1...7).contains(window.day) {
            let text = range(opens: window.opens, closes: window.closes)
            var ranges = rangesByDay[window.day] ?? []
            if !ranges.contains(text) { ranges.append(text) }
            rangesByDay[window.day] = ranges
        }

        return (1...7).compactMap { day in
            guard let ranges = rangesByDay[day], !ranges.isEmpty else { return nil }
            return "\(weekdayAbbreviations[day - 1]): \(ranges.joined(separator: ", ")) Uhr"
        }
    }

    /// Ein Zeitfenster: «08:00 – 12:00».
    static func range(opens: String, closes: String) -> String {
        "\(time(opens)) – \(time(closes))"
    }

    /// Uhrzeit ohne Sekunden: «09:00:00» → «09:00». Was sich nicht deuten
    /// lässt, bleibt unverändert stehen.
    static func time(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2 else { return trimmed }
        return "\(parts[0]):\(parts[1])"
    }

    // MARK: - Anzeigezeilen des Imports lesen

    /// Zerlegt die Anzeigezeilen des Imports in Zeitfenster, z. B.
    /// «Mo,Tu,We,Th,Fr 13:00:00-22:00:00», «Mo-Fr 09:00-18:00» oder
    /// «täglich 06:00-22:00». Zeilen ohne erkennbare Zeitangabe fallen weg.
    static func windows(fromDisplayLines lines: [String]) -> [Window] {
        var result: [Window] = []

        for line in lines {
            let tokens = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            // Das Zeitfenster ist der Abschnitt mit Doppelpunkt und Bindestrich.
            guard let timeToken = tokens.last(where: { $0.contains(":") && $0.contains("-") })
            else { continue }

            let timeParts = timeToken.split(separator: "-", maxSplits: 1).map(String.init)
            guard timeParts.count == 2 else { continue }

            let dayPart = tokens.filter { $0 != timeToken }.joined(separator: " ")
            for day in weekdays(in: dayPart) {
                result.append(Window(day: day, opens: timeParts[0], closes: timeParts[1]))
            }
        }

        return result
    }

    /// Wochentage aus einer Tagesangabe: «Mo,Tu,We», «Mo-Fr», «täglich».
    /// Ohne erkennbare Angabe gilt die Zeile für die ganze Woche – sonst
    /// verschwände sie ganz.
    static func weekdays(in text: String) -> [Int] {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty || everyDayKeywords.contains(where: { cleaned.contains($0) }) {
            return Array(1...7)
        }

        var days: [Int] = []
        for component in cleaned.split(whereSeparator: { $0 == "," || $0 == "+" || $0 == " " }) {
            let bounds = component.split(separator: "-").map(String.init)
            if bounds.count == 2, let from = dayNumbers[bounds[0]], let to = dayNumbers[bounds[1]] {
                // «Fr-Mo» läuft über das Wochenende hinweg weiter.
                var day = from
                days.append(day)
                while day != to {
                    day = day % 7 + 1
                    days.append(day)
                }
            } else if let day = dayNumbers[String(component)] {
                days.append(day)
            }
        }

        guard !days.isEmpty else { return Array(1...7) }
        return Array(Set(days)).sorted()
    }

    private static let everyDayKeywords = ["täglich", "taeglich", "daily", "jeden tag", "mo-so"]

    /// Tageskürzel und -namen, deutsch wie englisch.
    private static let dayNumbers: [String: Int] = [
        "mo": 1, "mon": 1, "monday": 1, "montag": 1,
        "tu": 2, "tue": 2, "tues": 2, "tuesday": 2, "di": 2, "die": 2, "dienstag": 2,
        "we": 3, "wed": 3, "wednesday": 3, "mi": 3, "mit": 3, "mittwoch": 3,
        "th": 4, "thu": 4, "thursday": 4, "do": 4, "don": 4, "donnerstag": 4,
        "fr": 5, "fri": 5, "friday": 5, "freitag": 5,
        "sa": 6, "sat": 6, "saturday": 6, "samstag": 6, "sonnabend": 6,
        "su": 7, "sun": 7, "sunday": 7, "so": 7, "son": 7, "sonntag": 7
    ]
}