// FieldTestService.swift
// Omina – Steuert den Feldtest-Modus (Altstadt Zürich, 3 Testtage).
//
// Ablauf pro Testperson:
//   1. Auf dem Welcome-Screen "Feldtest starten" → Testprofil (Bild + Name)
//      auswählen. Es wird ein anonymer Supabase-User erstellt (kein
//      Registrieren nötig) und eine Zeile in `test_participants` angelegt.
//   2. Die Testperson füllt das normale Onboarding mit ihren Daten aus;
//      das Ergebnis wird zusätzlich als JSON in `test_participants.profile`
//      gespeichert (separat von den regulären App-Daten).
//   3. Während des Tests schreibt TestAnalyticsService alle Interaktionen
//      in `test_events`.
//   4. Nach dem Test: "Test beenden" (Home, oben rechts) lädt offene Events
//      hoch und setzt das Gerät für die nächste Testperson zurück.
//
// Voraussetzung in Supabase: supabase/migrations/field_test_tables.sql ausführen und
// "Allow anonymous sign-ins" aktivieren (Authentication → Sign In / Providers).

import Foundation
import Combine
import UIKit
import Supabase

/// Aktiver Testlauf einer Testperson. Wird in den UserDefaults persistiert,
/// damit ein App-Neustart den Testlauf nicht beendet.
struct FieldTestSession: Codable {
    let profileKey: String
    let firstName: String
    let lastName: String
    /// Pro Testlauf konstante ID, um Events eines Durchgangs zu gruppieren.
    let sessionId: UUID
    let startedAt: Date

    var displayName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum FieldTestError: GermanLocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Kein Test-User angemeldet. Bitte Testprofil erneut auswählen."
        }
    }
}

@MainActor
final class FieldTestService: ObservableObject {
    static let shared = FieldTestService()

    @Published private(set) var activeSession: FieldTestSession?

    private let client = SupabaseService.shared.client
    private static let sessionKey = "omina.fieldTest.session"

    private init() {
        activeSession = Self.loadPersistedSession()
    }

    /// Feldtest läuft: Feature-Flag an UND eine Testperson hat ein Profil gewählt.
    var isActive: Bool {
        AppConfig.fieldTestModeEnabled && activeSession != nil
    }

    // MARK: - Testlauf starten (Profil-Auswahl)

    /// Meldet einen anonymen Supabase-User an und startet den Testlauf für
    /// das gewählte Testprofil.
    func startTest(with profile: TestProfile) async throws {
        try await AuthService.shared.signInAnonymously()

        let session = FieldTestSession(
            profileKey: profile.key,
            firstName: profile.firstName,
            lastName: profile.lastName,
            sessionId: UUID(),
            startedAt: Date()
        )
        activeSession = session
        persist(session)

        // Teilnehmer-Zeile anlegen. Best effort: schlägt das fehl (z. B. kurz
        // offline), wird sie beim Speichern des Onboardings per Upsert
        // nachgeholt.
        try? await upsertParticipant(profile: nil)

        TestAnalyticsService.shared.track(
            "test_started",
            properties: ["test_profile": profile.key, "name": profile.displayName]
        )
    }

    // MARK: - Onboarding-Daten separat speichern

    /// Schreibt die Onboarding-Antworten der Testperson als JSON in
    /// `test_participants.profile`.
    func saveOnboardingProfile(_ profile: UserProfile) async throws {
        try await upsertParticipant(profile: profile)
    }

    private func upsertParticipant(profile: UserProfile?) async throws {
        guard let session = activeSession else { return }
        guard let userId = AuthService.shared.currentUser?.id else {
            throw FieldTestError.notAuthenticated
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "Europe/Zurich")

        let appVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        let row = ParticipantRow(
            userId: userId,
            testProfileKey: session.profileKey,
            displayName: session.displayName,
            testDay: dayFormatter.string(from: session.startedAt),
            profile: profile,
            deviceModel: "\(UIDevice.current.model) (iOS \(UIDevice.current.systemVersion))",
            appVersion: appVersion,
            updatedAt: Date()
        )

        try await client
            .from("test_participants")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    // MARK: - Testlauf beenden (Gerät für nächste Testperson zurücksetzen)

    /// Lädt offene Events hoch, meldet den anonymen User ab und löscht alle
    /// lokalen Zustände (Consent, Profil-Cache, Notification-Flag), damit die
    /// nächste Testperson wieder ganz vorne startet.
    func endTest() async {
        TestAnalyticsService.shared.track("test_ended")
        await TestAnalyticsService.shared.flushNow()

        activeSession = nil
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        ProfileService.shared.deleteLocalProfile()
        ConsentStore.reset()
        NotificationPermissionStore.reset()
        OnboardingPermissionsStore.reset()

        try? await AuthService.shared.signOut()
    }

    // MARK: - Persistenz

    private func persist(_ session: FieldTestSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    private static func loadPersistedSession() -> FieldTestSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FieldTestSession.self, from: data)
    }
}

/// Eine Zeile in `test_participants`.
private struct ParticipantRow: Encodable {
    let userId: UUID
    let testProfileKey: String
    let displayName: String
    let testDay: String
    let profile: UserProfile?
    let deviceModel: String?
    let appVersion: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case testProfileKey = "test_profile_key"
        case displayName = "display_name"
        case testDay = "test_day"
        case profile
        case deviceModel = "device_model"
        case appVersion = "app_version"
        case updatedAt = "updated_at"
    }
}