// ConsentView.swift
// Omina
//
// Datenschutz-Screen nach Entwurf: Akzentleiste unter der Statusleiste, Titel
// mit Einleitung, drei Hinweiskarten zu den verarbeiteten Daten, der Link auf
// die ausführliche Erklärung und – nach Apples Muster für den "Daten &
// Datenschutz"-Screen – ein einzelner Fortfahren-Button.
//
// Rechtlich gilt Apples Standard-Lizenzvertrag für lizenzierte Apps
// (Standard-EULA) statt eigener Nutzungsbedingungen; die Zustimmung erfolgt
// durch Tippen auf "Fortfahren". Der Zeitpunkt wird lokal persistiert.

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
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    header

                    InfoCard(
                        icon: "location.fill",
                        title: "Standort",
                        detail: "Zeigt Barrieren in deiner Nähe. Keine Ortung im Hintergrund."
                    )
                    InfoCard(
                        icon: "camera.fill",
                        title: "Kamera",
                        detail: "Nur für die AR-Ansicht. Es werden keine Aufnahmen gespeichert."
                    )
                    InfoCard(
                        icon: "person.crop.rectangle.fill",
                        title: "Profildaten",
                        detail: "Dein Mobilitätsprofil, verschlüsselt gespeichert (Supabase, EU-Region)."
                    )

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Text("Weitere Informationen zum Datenschutz …")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.accentPrimary)
                            .frame(minHeight: AppMetrics.Touch.minimum, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .padding(.top, AppMetrics.Space.s)

                    legalNotice
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.m)
            }

            footer
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        // Wie im Entwurf ohne Navigationsleiste; die Akzentleiste sitzt direkt
        // unter der Statusleiste.
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
            Text("Datenschutz")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Text("Omina verarbeitet nur die Daten, die für die Barriere-Warnungen nötig sind – und nur, während du die App nutzt. Nichts davon wird weiterverkauft oder für Werbung genutzt.")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, AppMetrics.Space.xxl + AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.l)
    }

    /// Zustimmung durch Fortfahren – rechtliche Grundlage ist Apples
    /// Standard-EULA.
    private var legalNotice: some View {
        Text("Mit «Fortfahren» akzeptierst du den [Standard-Lizenzvertrag (EULA) von Apple](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) und die Datenschutzerklärung. Du kannst deine Daten in den Einstellungen jederzeit einsehen und löschen.")
            .font(AppTypography.body)
            .foregroundStyle(AppColor.textSecondary)
            .tint(AppColor.accentPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, AppMetrics.Space.xxl)
    }

    private var footer: some View {
        Button {
            ConsentStore.recordConsent()
            TestAnalyticsService.shared.track("consent_given", screen: "consent")
            onContinue()
        } label: {
            Text("Fortfahren")
        }
        .buttonStyle(.appPrimary)
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }
}

#Preview {
    NavigationStack {
        ConsentView(onContinue: {})
    }
}