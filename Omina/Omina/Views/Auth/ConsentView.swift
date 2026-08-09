// ConsentView.swift
// Omina
//
// Datenschutz-Hinweis nach Apples eigenem Muster ("Daten & Datenschutz"-
// Splash-Screen): Icon, Titel, Daten-Übersicht, Link auf Details und ein
// einzelner Fortfahren-Button. Rechtlich gilt Apples Standard-Lizenzvertrag
// für lizenzierte Apps (Standard-EULA) statt eigener Nutzungsbedingungen;
// die Zustimmung erfolgt – wie bei Apple üblich – durch Tippen auf
// "Fortfahren". Der Zeitpunkt wird lokal persistiert.

import SwiftUI

enum ConsentStore {
    private static let key = "omina.consentGivenAt"

    static var hasConsent: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static func recordConsent() {
        UserDefaults.standard.set(Date(), forKey: key)
    }

    /// Feldtest: Consent zurücksetzen, damit die nächste Testperson auf dem
    /// gleichen Gerät wieder gefragt wird.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct ConsentView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .padding(.top, 48)

                    Text("Daten & Datenschutz")
                        .font(.title)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Omina verarbeitet nur die Daten, die für die Barriere-Warnungen nötig sind – und nur, während du die App nutzt.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    VStack(spacing: 12) {
                        dataRow(
                            symbolName: "location.fill",
                            title: "Standort",
                            detail: "Zeigt Barrieren in deiner Nähe. Keine Ortung im Hintergrund."
                        )
                        dataRow(
                            symbolName: "camera.fill",
                            title: "Kamera",
                            detail: "Nur für die AR-Ansicht. Es werden keine Aufnahmen gespeichert."
                        )
                        dataRow(
                            symbolName: "person.crop.rectangle.fill",
                            title: "Profildaten",
                            detail: "Dein Mobilitätsprofil, verschlüsselt gespeichert (Supabase, EU-Region)."
                        )
                    }
                    .padding(.top, 8)

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Text("Weitere Informationen zum Datenschutz …")
                            .font(.footnote)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
            }

            // Fusszeile nach Apple-Muster: Zustimmung durch Fortfahren,
            // rechtliche Grundlage ist Apples Standard-EULA.
            VStack(spacing: 12) {
                Text("Durch Tippen auf „Fortfahren“ akzeptierst du den [Standard-Lizenzvertrag (EULA) von Apple](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) und die Datenschutzerklärung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button {
                    ConsentStore.recordConsent()
                    TestAnalyticsService.shared.track("consent_given", screen: "consent")
                    onContinue()
                } label: {
                    Text("Fortfahren")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func dataRow(symbolName: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}