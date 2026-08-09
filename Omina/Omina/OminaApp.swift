// OminaApp.swift
// Omina
//
// App Entry Point - Routes basierend auf Auth-State

import SwiftUI
import Supabase
import Auth

@main
struct OminaApp: App {
    @StateObject private var authService = AuthService.shared

    init() {
        // UNUserNotificationCenter-Delegate früh setzen, damit Barriere-
        // Warnungen als System-Mitteilungen zugestellt und Taps darauf
        // verarbeitet werden können.
        BarrierNotificationService.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                // Leitfarbe app-weit: Toggles, Slider und andere getönte
                // System-Controls ziehen sich sonst das System-Grün; mit dem
                // globalen Tint erscheinen sie durchgängig im Violett der
                // Marke (§02 Farbsystem).
                .tint(AppColor.accentPrimary)
                // Prototyp ist bewusst nur auf Deutsch (Schweiz): Datums- und
                // Zahlenformate app-weit auf Deutsch fixieren, unabhängig von
                // der Gerätesprache (Wochentag, Monat, relative Daten …).
                .environment(\.locale, Locale(identifier: "de_CH"))
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if authService.isLoading {
                SplashView()
            } else if authService.isAuthenticated {
                AuthenticatedRootView()
            } else {
                WelcomeView()
            }
        }
    }
}

// Routet nach erfolgreichem Login:
// Consent (Datenschutz) → Berechtigungen (einmalig: Standort/Kamera/
// Mitteilungen über Apples System-Prompts) → Onboarding (wenn kein Profil) →
// Home. Danach werden keine eigenen Berechtigungs-Screens mehr gezeigt. Hält
// das Profil separat, damit es als Binding an HomeView und weiter an Settings
// gereicht werden kann (S1).
struct AuthenticatedRootView: View {
    @EnvironmentObject var authService: AuthService
    @State private var profile: UserProfile?
    @State private var loadState: LoadState = .loading
    @State private var hasConsent = ConsentStore.hasConsent
    @State private var permissionsPrimed = OnboardingPermissionsStore.completed

    enum LoadState {
        case loading
        case needsOnboarding
        case ready
    }

    var body: some View {
        Group {
            if !hasConsent {
                NavigationStack {
                    ConsentView {
                        hasConsent = true
                    }
                }
            } else if !permissionsPrimed {
                // Direkt nach dem Datenschutz-Screen: einmalige Einwilligung
                // für Standort, Kamera und Mitteilungen. Danach wird im
                // laufenden Betrieb höchstens noch Apples System-Prompt gezeigt.
                OnboardingPermissionsView {
                    permissionsPrimed = true
                }
            } else {
                switch loadState {
                case .loading:
                    SplashView()
                case .needsOnboarding:
                    OnboardingCoordinator {
                        Task { await checkProfile() }
                    }
                case .ready:
                    HomeView(profile: profileBinding)
                }
            }
        }
        .task {
            await checkProfile()
        }
    }

    private var profileBinding: Binding<UserProfile> {
        Binding(
            get: { profile ?? .placeholder },
            set: { newValue in
                profile = newValue
                Task { try? await ProfileService.shared.saveProfile(newValue) }
            }
        )
    }

    private func checkProfile() async {
        loadState = .loading
        do {
            if let loaded = try await ProfileService.shared.loadProfile() {
                profile = loaded
                loadState = .ready
            } else {
                loadState = .needsOnboarding
            }
        } catch {
            loadState = .needsOnboarding
        }
    }
}

private extension UserProfile {
    static var placeholder: UserProfile {
        UserProfile(
            id: UUID(),
            mobilityCategory: .wheelchair,
            wheelchairType: .manual,
            widthCm: 65,
            heightCm: 130,
            weightKg: 75,
            seatHeightCm: 50,
            lengthCm: 110,
            maxIncline: 6,
            maxCurbHeight: 3,
            surfaceTolerance: .fineCobble,
            companionStatus: .alwaysAlone,
            companionTodayOverride: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}