// OnboardingProgressBar.swift
// Omina – Geteilte Chrome (Fortschritt, Titel, Navigation) für alle
// Onboarding-Screens. Styling ausschliesslich über Design-Tokens
// (AppColor, AppTypography, AppMetrics) und die gemeinsamen Button-Stile.

import SwiftUI

struct OnboardingProgressBar: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: AppMetrics.Space.s) {
            HStack(spacing: AppMetrics.Space.xs + 2) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue
                              ? AppColor.accentPrimary
                              : AppColor.borderDecorative)
                        .frame(height: 5)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }

            HStack {
                Text("Schritt \(step.rawValue) von \(OnboardingStep.allCases.count)")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, AppMetrics.Space.m)
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
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(step.subtitle)
                .font(AppTypography.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppMetrics.Space.m)
        .padding(.top, AppMetrics.Space.m)
    }
}

struct OnboardingNavigationBar: View {
    let canProceed: Bool
    let isLastStep: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Button(action: onBack) {
                Label("Zurück", systemImage: "chevron.left")
            }
            .buttonStyle(.appSecondary(fullWidth: true))

            Button(action: onNext) {
                Text(isLastStep ? "Fertig" : "Weiter")
            }
            .buttonStyle(.appPrimary(fullWidth: true))
            .disabled(!canProceed)
            .opacity(canProceed ? 1 : 0.5)
        }
        .padding(.horizontal, AppMetrics.Space.m)
        .padding(.top, AppMetrics.Space.s)
        .padding(.bottom, AppMetrics.Space.m)
        .background(AppColor.backgroundPrimary)
    }
}