// TestProfile.swift
// Omina – Vorgefertigte Profile für den Feldtest Altstadt Zürich.
//
// Testpersonen registrieren sich nicht, sondern wählen eines dieser Profile
// (Bild + Name) aus und durchlaufen danach nur noch das Onboarding mit ihren
// eigenen Angaben. Den Nachnamen tragen sie dort selbst ein.

import SwiftUI

struct TestProfile: Identifiable, Hashable {
    /// Stabiler Schlüssel, unter dem Teilnehmer- und Event-Daten in der
    /// Datenbank abgelegt werden (test_profile_key).
    let key: String
    let firstName: String
    let lastName: String

    var id: String { key }

    var displayName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var initials: String {
        let first = firstName.prefix(1)
        let last = lastName.prefix(1)
        return "\(first)\(last)"
    }

    /// Avatar-Grundfarbe aus der Violett-Palette des Design-Systems. Jedes
    /// Profil erhält eine eigene Stufe – markenkonform und trotzdem visuell
    /// unterscheidbar. Alle Stufen sind dunkel genug für weisse Initialen.
    var avatarColor: Color {
        switch key {
        case "tp01": return AppColor.Violet.v500
        case "tp02": return AppColor.Violet.v600
        case "tp03": return AppColor.Violet.v700
        case "tp04": return AppColor.Violet.v800
        case "tp05": return AppColor.Violet.v900
        default:     return AppColor.Violet.v950
        }
    }

    /// Die 6 Testpersonen der 3 Testtage, alphabetisch sortiert.
    /// Fehlt der Nachname, trägt ihn die Testperson im Onboarding selbst ein.
    static let all: [TestProfile] = [
        TestProfile(key: "tp01", firstName: "Alessio", lastName: ""),
        TestProfile(key: "tp02", firstName: "Annette", lastName: "Suter"),
        TestProfile(key: "tp03", firstName: "Edith",   lastName: "Schwitter"),
        TestProfile(key: "tp04", firstName: "Livia",   lastName: "Künzler"),
        TestProfile(key: "tp05", firstName: "Taz",     lastName: ""),
        TestProfile(key: "tp06", firstName: "Ursula",  lastName: "Meier")
    ]

    static func byKey(_ key: String) -> TestProfile? {
        all.first { $0.key == key }
    }
}

/// Rundes Avatar-Bild eines Testprofils im App-Stil: gefüllter Kreis in einer
/// Violett-Stufe des Design-Systems + weisse Initialen, mit weichem Schatten
/// (wie die Avatare auf Home/Profil). Jedes Profil erhält eine eigene Stufe,
/// bleibt also markenkonform und trotzdem visuell unterscheidbar.
struct TestProfileAvatar: View {
    let profile: TestProfile
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .fill(profile.avatarColor)
            // Immer weiss: die Violett-Stufen sind in beiden Modi dunkel.
            Text(profile.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppColor.Violet.v950.opacity(0.18), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}