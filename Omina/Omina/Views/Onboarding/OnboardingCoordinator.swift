// OnboardingCoordinator.swift
// Omina – Container-View, die zwischen den acht Onboarding-Screens wechselt.
// Reihenfolge gemäss Entwurf; gespeichert wird am Ende des letzten Schritts
// (Handy-Ausrichtung). Der Speicherzustand steht über der Fusszeile, damit er
// unabhängig vom gerade sichtbaren Schritt erscheint.

import SwiftUI

struct OnboardingCoordinator: View {
    @StateObject private var viewModel = OnboardingViewModel()
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(step: viewModel.currentStep)
                .padding(.top, AppMetrics.Space.s + AppMetrics.Space.xs)

            OnboardingHeader(step: viewModel.currentStep)

            ScrollView {
                Group {
                    switch viewModel.currentStep {
                    case .profileSetup:
                        Screen10_ProfileSetup(draft: $viewModel.draft)
                    case .mobilityCategory:
                        Screen11_MobilityCategory(draft: $viewModel.draft)
                    case .wheelchairType:
                        Screen12_WheelchairType(
                            draft: $viewModel.draft,
                            onSelect: viewModel.selectWheelchairSubtype
                        )
                    case .measurements:
                        Screen13_Measurements(draft: $viewModel.draft)
                    case .abilities:
                        Screen14_Abilities(draft: $viewModel.draft)
                    case .support:
                        Screen15_Support(draft: $viewModel.draft)
                    case .summary:
                        Screen16_Summary(draft: viewModel.draft)
                    case .phoneSetup:
                        PhoneOrientationScreen()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.xl)
                .padding(.bottom, AppMetrics.Space.m)
            }
            // Bei jedem Schritt eine frische ScrollView: der Inhalt beginnt
            // immer oben, sodass das erste Eingabefeld ganz oben erscheint
            // (kein übernommener Scroll-Offset vom vorherigen Schritt).
            .id(viewModel.currentStep)

            saveState

            OnboardingNavigationBar(
                canProceed: viewModel.canProceed && !viewModel.isSaving,
                isLastStep: viewModel.isLastStep,
                onBack: viewModel.back,
                onNext: {
                    if viewModel.isLastStep {
                        Task {
                            await viewModel.saveProfile()
                        }
                    } else {
                        viewModel.next()
                    }
                }
            )
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .onChange(of: viewModel.didComplete) { _, completed in
            if completed { onFinish() }
        }
    }

    /// Rückmeldung zum Speichern – erscheint über der Fusszeile, sobald der
    /// letzte Schritt abgeschickt wurde.
    @ViewBuilder
    private var saveState: some View {
        if viewModel.isSaving {
            HStack(spacing: AppMetrics.Space.s) {
                ProgressView()
                    .tint(AppColor.accentPrimary)
                Text("Profil wird gespeichert …")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppMetrics.Space.l)
        }

        if let errorMessage = viewModel.errorMessage {
            HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.Status.blockedIcon)
                Text(errorMessage)
                    .foregroundStyle(AppColor.Status.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppTypography.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppMetrics.Space.s + AppMetrics.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.field, style: .continuous)
                    .fill(AppColor.Status.blockedFill)
            )
            .padding(.horizontal, AppMetrics.Space.l)
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    OnboardingCoordinator(onFinish: {})
}