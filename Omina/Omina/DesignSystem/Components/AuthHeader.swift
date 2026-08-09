// AuthHeader.swift
// Omina
//
// Kopfbereich der Screens ohne Navigationsleiste (Willkommen, Anmelden,
// Registrieren, Passwort, Datenschutz, Zugriff erlauben): grosser Titel im
// Markenviolett, darunter eine erklärende Zeile. Abstände nach Entwurf – der
// Titel beginnt rund 60 pt unter der Akzentleiste.

import SwiftUI

struct AuthHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text(title)
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppMetrics.Space.xxl + AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.l)
    }
}

#Preview {
    VStack(spacing: 0) {
        BrandAccentBar()
        AuthHeader(
            title: "Willkommen zurück!",
            subtitle: "Melde dich an, um deine Route weiterzuplanen."
        )
        .padding(.horizontal, AppMetrics.Space.l)
        Spacer()
    }
    .background(AppColor.backgroundPrimary)
}