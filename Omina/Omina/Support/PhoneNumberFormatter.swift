// PhoneNumberFormatter.swift
// Omina
//
// Formatiert die Telefonnummer, während sie eingegeben wird: aus «791234567»
// wird «79 123 45 67» (Gruppen 2-3-2-2, schweizerische Schreibweise ohne
// Vorwahl). Die Landesvorwahl steht im Formular in einem eigenen Feld davor,
// deshalb kennt der Formatierer nur den nationalen Teil.

import Foundation

// `nonisolated` wie die übrigen reinen Formatierer (siehe OSMSurfaceRating):
// Das Projekt baut mit MainActor als Standard-Isolation, hier wird aber nur
// gerechnet.
nonisolated enum PhoneNumberFormatter {

    /// Stellen einer schweizerischen Nummer ohne Vorwahl und ohne die
    /// führende 0 (z. B. 79 123 45 67).
    static let maxDigits = 9

    /// Gruppengrössen der Anzeige: «00 000 00 00».
    private static let groupLengths = [2, 3, 2, 2]

    /// Eingabe in die Anzeigeform bringen. Alles, was keine Ziffer ist, fällt
    /// weg; eine führende 0 ebenfalls, weil sie mit der Landesvorwahl nicht
    /// mitgewählt wird (079 … → +41 79 …).
    static func formatted(_ input: String) -> String {
        let digits = self.digits(input)
        var groups: [String] = []
        var index = digits.startIndex

        for length in groupLengths {
            guard index < digits.endIndex else { break }
            let end = digits.index(index, offsetBy: length, limitedBy: digits.endIndex)
                ?? digits.endIndex
            groups.append(String(digits[index..<end]))
            index = end
        }

        return groups.joined(separator: " ")
    }

    /// Reine Ziffernfolge der Nummer (ohne Leerzeichen, ohne führende 0),
    /// gekappt auf `maxDigits`.
    static func digits(_ input: String) -> String {
        var digits = input.filter(\.isNumber)
        while digits.first == "0" {
            digits.removeFirst()
        }
        return String(digits.prefix(maxDigits))
    }

    /// Nummer in internationaler Schreibweise für die Ablage im Konto,
    /// z. B. «+41791234567». Leere Eingabe ergibt einen leeren String, damit
    /// die freiwillige Angabe auch weggelassen werden kann.
    static func internationalNumber(dialCode: String, national: String) -> String {
        let digits = self.digits(national)
        guard !digits.isEmpty else { return "" }
        let code = dialCode.filter(\.isNumber)
        return "+\(code)\(digits)"
    }
}