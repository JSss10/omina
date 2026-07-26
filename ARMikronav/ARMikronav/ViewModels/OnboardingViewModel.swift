// OnboardingViewModel.swift
// ARMikronav – State Management für den 6-stufigen Onboarding-Flow.

import Foundation
import SwiftUI
import Combine
import Auth
import Supabase

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .profileSetup
    @Published var draft: DraftProfile = DraftProfile()
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var didComplete: Bool = false

    private let profileService: ProfileServiceProtocol

    init(profileService: ProfileServiceProtocol? = nil) {
        self.profileService = profileService ?? ProfileService.shared
        prefillNamesFromAuth()
    }

    /// Screen 1.0: Vor-/Nachname vorbelegen. Im Feldtest kommt der Name aus
    /// dem gewählten Testprofil, sonst aus der Registrierung (user_metadata).
    private func prefillNamesFromAuth() {
        if let session = FieldTestService.shared.activeSession {
            draft.firstName = session.firstName
            draft.lastName = session.lastName
            return
        }
        guard let metadata = AuthService.shared.currentUser?.userMetadata else { return }
        if case .string(let first) = metadata["first_name"] {
            draft.firstName = first
        }
        if case .string(let last) = metadata["last_name"] {
            draft.lastName = last
        }
    }

    // MARK: - Navigation

    func next() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        TestAnalyticsService.shared.track(
            "onboarding_next",
            screen: "onboarding",
            properties: ["from": String(describing: currentStep), "to": String(describing: nextStep)]
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = nextStep
        }
    }

    func back() {
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        TestAnalyticsService.shared.track(
            "onboarding_back",
            screen: "onboarding",
            properties: ["from": String(describing: currentStep), "to": String(describing: prevStep)]
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = prevStep
        }
    }

    // MARK: - Step Validation

    var canProceed: Bool {
        switch currentStep {
        case .profileSetup:
            return !draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !draft.lastName.trimmingCharacters(in: .whitespaces).isEmpty
        case .mobilityCategory:
            return draft.mobilityCategory == .wheelchair
        case .wheelchairType:
            return draft.wheelchairSubtype != nil
        case .measurements, .phoneSetup, .abilities, .support:
            return true
        case .summary:
            return draft.isComplete
        }
    }

    // MARK: - Screen 1.2 Side Effect

    func selectWheelchairSubtype(_ subtype: WheelchairSubtype) {
        draft.wheelchairSubtype = subtype
        draft.applyDefaults(for: subtype)
    }

    // MARK: - Save (Screen 1.6)

    func saveProfile() async {
        guard let userId = profileService.currentUserId else {
            errorMessage = "Nicht eingeloggt. Bitte erneut anmelden."
            return
        }
        guard let profile = draft.buildUserProfile(userId: userId) else {
            errorMessage = "Profil ist unvollständig."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            // Feldtest: Onboarding-Daten zusätzlich separat in die
            // Test-Datenbank schreiben (test_participants.profile). Bewusst
            // nicht best effort – schlägt das fehl, soll es am Testtag
            // auffallen und erneut versucht werden können.
            if FieldTestService.shared.isActive {
                try await FieldTestService.shared.saveOnboardingProfile(profile)
            }

            try await profileService.saveProfile(profile)
            await syncNamesToAuth()
            TestAnalyticsService.shared.track("onboarding_completed", screen: "onboarding")
            didComplete = true
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Best-effort: Namen aus Screen 1.0 zurück in die Auth-user_metadata schreiben
    /// (relevant, wenn der User sie im Onboarding geändert hat).
    private func syncNamesToAuth() async {
        let attributes = UserAttributes(data: [
            "first_name": .string(draft.firstName),
            "last_name": .string(draft.lastName)
        ])
        _ = try? await SupabaseService.shared.client.auth.update(user: attributes)
    }
}

// MARK: - OnboardingStep

enum OnboardingStep: Int, CaseIterable {
    case profileSetup     = 1
    case mobilityCategory = 2
    case wheelchairType   = 3
    case measurements     = 4
    case phoneSetup       = 5
    case abilities        = 6
    case support          = 7
    case summary          = 8

    var progress: Double {
        Double(rawValue) / Double(Self.allCases.count)
    }

    var title: String {
        switch self {
        case .profileSetup:     return "Wer bist du?"
        case .mobilityCategory: return "Wie bist du unterwegs?"
        case .wheelchairType:   return "Dein Rollstuhl"
        case .measurements:     return "Masse"
        case .phoneSetup:       return "Handy-Ausrichtung"
        case .abilities:        return "Deine Fähigkeiten"
        case .support:          return "Unterstützung"
        case .summary:          return "Zusammenfassung"
        }
    }

    var subtitle: String {
        switch self {
        case .profileSetup:     return "Dein Name für das Profil"
        case .mobilityCategory: return "Wähle deine Mobilitätssituation"
        case .wheelchairType:   return "Welchen Rollstuhl nutzt du?"
        case .measurements:     return "Für genauere Barrierenwarnungen"
        case .phoneSetup:       return "So richtest du dein iPhone für AR aus"
        case .abilities:        return "Was traust du dir im Alltag zu?"
        case .support:          return "Bist du meist allein unterwegs?"
        case .summary:          return "Überprüfe dein Profil"
        }
    }
}