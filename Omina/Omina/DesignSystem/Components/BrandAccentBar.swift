// BrandAccentBar.swift
// Omina
//
// Die violette Leiste direkt unter der Statusleiste, die im Entwurf über allen
// Screens ohne Navigationsleiste steht (Intro, Registrierung, Datenschutz,
// Zugriff erlauben). Rein dekorativ – sie zeigt keinen Fortschritt und ist für
// VoiceOver unsichtbar. Den Fortschritt im Onboarding zeigt stattdessen
// OnboardingProgressBar.

import SwiftUI

struct BrandAccentBar: View {
    var body: some View {
        Capsule()
            .fill(AppColor.Violet.v500)
            .frame(height: 4)
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.top, AppMetrics.Space.s + AppMetrics.Space.xs)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        BrandAccentBar()
        Spacer()
    }
    .background(AppColor.backgroundPrimary)
}