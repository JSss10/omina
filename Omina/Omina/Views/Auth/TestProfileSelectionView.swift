// TestProfileSelectionView.swift
// Omina – Feldtest: Auswahl eines vorgefertigten Testprofils.
//
// Testpersonen wählen hier statt einer Registrierung einfach ihr Profil
// (Bild + Name) aus. Danach läuft der normale Flow weiter:
// Consent → Onboarding (mit den eigenen Daten) → Home.

import SwiftUI

struct TestProfileSelectionView: View {
    @State private var startingProfileKey: String?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: AppMetrics.Space.m),
        GridItem(.flexible(), spacing: AppMetrics.Space.m)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppMetrics.Space.l) {
                Text("Wähle dein Testprofil und tippe es an – danach beantwortest du ein paar Fragen zu dir.")
                    .font(AppTypography.body)
                    .foregroundColor(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppMetrics.Space.l)
                    .padding(.top, AppMetrics.Space.m)

                LazyVGrid(columns: columns, spacing: AppMetrics.Space.m) {
                    // Alphabetisch nach Name sortiert.
                    ForEach(TestProfile.all.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }) { profile in
                        profileCard(profile)
                    }
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.xxl)
            }
        }
        .navigationTitle("Testprofil wählen")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(startingProfileKey != nil)
        .alert(
            "Start fehlgeschlagen",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func profileCard(_ profile: TestProfile) -> some View {
        Button {
            start(profile)
        } label: {
            VStack(spacing: AppMetrics.Space.m) {
                ZStack {
                    TestProfileAvatar(profile: profile, size: 88)
                    if startingProfileKey == profile.key {
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 88, height: 88)
                        ProgressView()
                            .tint(.white)
                    }
                }

                Text(profile.displayName)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppMetrics.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(TestProfileButtonStyle())
        .accessibilityLabel("Testprofil \(profile.displayName) auswählen")
    }

    private func start(_ profile: TestProfile) {
        guard startingProfileKey == nil else { return }
        startingProfileKey = profile.key

        Task {
            do {
                try await FieldTestService.shared.startTest(with: profile)
                // Kein manuelles Weiter-Navigieren nötig: RootView wechselt
                // durch den Auth-State automatisch zu Consent/Onboarding.
            } catch {
                errorMessage = ErrorText.message(for: error, context: "Testprofil konnte nicht gestartet werden")
                startingProfileKey = nil
            }
        }
    }
}

/// Dezentes Tipp-Feedback für die Profil-Kreise (leichtes Skalieren statt
/// gefüllter Kachel), passend zum Kreis-Design der App.
private struct TestProfileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        TestProfileSelectionView()
    }
}