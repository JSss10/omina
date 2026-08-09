// OnboardingProgressBar.swift
// Omina – Geteilte Chrome (Fortschritt, Titel, Navigation) für alle
// Onboarding-Screens, aufgebaut nach dem Entwurf: acht Segmente direkt unter
// der Statusleiste, darunter «Schritt x von 8», dann Titel und Unterzeile.
// Am unteren Rand stehen «Zurück» und «Weiter» nebeneinander, gleich breit.
//
// Styling ausschliesslich über Design-Tokens (AppColor, AppTypography,
// AppMetrics) und die gemeinsamen Button-Stile.

import SwiftUI

struct OnboardingProgressBar: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            HStack(spacing: AppMetrics.Space.xs) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(AppColor.accentPrimary.opacity(s.rawValue <= step.rawValue ? 1 : 0.3))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }

            Text("Schritt \(step.rawValue) von \(OnboardingStep.allCases.count)")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(step.rawValue) von \(OnboardingStep.allCases.count)")
    }
}

struct OnboardingHeader: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text(step.title)
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)
            Text(step.subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.xl)
    }
}

struct OnboardingNavigationBar: View {
    let canProceed: Bool
    let isLastStep: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            Button(action: onBack) {
                NavigationActionLabel(title: "Zurück", direction: .back)
            }
            .buttonStyle(.appSecondary(fullWidth: true))

            Button(action: onNext) {
                NavigationActionLabel(title: isLastStep ? "Fertig" : "Weiter")
            }
            .buttonStyle(.appPrimary(fullWidth: true))
            // Inaktiv zeigt der Primär-Button die gedämpfte Fläche aus dem
            // Entwurf; er bleibt sichtbar, statt auszugrauen.
            .disabled(!canProceed)
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }
}

#Preview {
    VStack(spacing: 0) {
        OnboardingProgressBar(step: .wheelchairType)
            .padding(.top, AppMetrics.Space.s + AppMetrics.Space.xs)
        OnboardingHeader(step: .wheelchairType)
        Spacer()
        OnboardingNavigationBar(
            canProceed: false,
            isLastStep: false,
            onBack: {},
            onNext: {}
        )
    }
    .background(AppColor.backgroundPrimary)
}