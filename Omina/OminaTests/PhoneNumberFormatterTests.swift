// PhoneNumberFormatterTests.swift
// OminaTests
//
// Tests für die Telefonnummer im Registrierungsformular: Sie wird beim Tippen
// in die Gruppen «00 000 00 00» gebracht und für das Konto in die
// internationale Schreibweise übersetzt.

import Testing
@testable import Omina

// Das Test-Target baut ohne MainActor-Standardisolation, die App-Typen
// aber mit. @MainActor hier hält die Aufrufe in dieselbe Isolation.
@MainActor
struct PhoneNumberFormatterTests {

    /// Die Gruppen entstehen, während getippt wird.
    @Test func groupsDigitsWhileTyping() {
        #expect(PhoneNumberFormatter.formatted("7") == "7")
        #expect(PhoneNumberFormatter.formatted("79") == "79")
        #expect(PhoneNumberFormatter.formatted("791") == "79 1")
        #expect(PhoneNumberFormatter.formatted("79123") == "79 123")
        #expect(PhoneNumberFormatter.formatted("7912345") == "79 123 45")
        #expect(PhoneNumberFormatter.formatted("791234567") == "79 123 45 67")
    }

    /// Bereits formatierte Eingaben bleiben stabil (der Formatierer läuft bei
    /// jedem Tastendruck erneut über seinen eigenen Text).
    @Test func formattingIsIdempotent() {
        let once = PhoneNumberFormatter.formatted("791234567")
        #expect(PhoneNumberFormatter.formatted(once) == once)
    }

    /// Die führende 0 fällt weg – sie wird mit der Vorwahl nicht gewählt.
    @Test func dropsTheTrunkPrefix() {
        #expect(PhoneNumberFormatter.formatted("0791234567") == "79 123 45 67")
    }

    /// Alles, was keine Ziffer ist, wird ignoriert; über neun Stellen hinaus
    /// wird nichts mehr übernommen.
    @Test func ignoresOtherCharactersAndExtraDigits() {
        #expect(PhoneNumberFormatter.formatted("79-123/45 67") == "79 123 45 67")
        #expect(PhoneNumberFormatter.formatted("7912345678999") == "79 123 45 67")
    }

    /// Für das Konto zählt die internationale Form, ohne Leerzeichen.
    @Test func buildsTheInternationalNumber() {
        #expect(
            PhoneNumberFormatter.internationalNumber(dialCode: "+ 41", national: "79 123 45 67")
                == "+41791234567"
        )
    }

    /// Ohne Eingabe bleibt die freiwillige Angabe leer.
    @Test func emptyInputStaysEmpty() {
        #expect(PhoneNumberFormatter.formatted("") == "")
        #expect(PhoneNumberFormatter.internationalNumber(dialCode: "+ 41", national: "") == "")
    }
}