// ProfileService.swift
// Omina – Service zum Speichern des UserProfile.
//
// Offline-first: das Profil liegt primär in UserDefaults, damit App-Start und
// Edits ohne Netzwerk funktionieren. Beim Speichern wird zusätzlich ein
// Best-Effort-Sync auf Supabase user_metadata gefahren. Beim Laden auf einem
// frischen Gerät (UserDefaults leer) holt sich der Service das Profil aus
// user_metadata zurück und cached es lokal. (B1)

import Foundation
import Auth
import Supabase

protocol ProfileServiceProtocol: Sendable {
    var currentUserId: UUID? { get }
    func saveProfile(_ profile: UserProfile) async throws
    func loadProfile() async throws -> UserProfile?
}

final class ProfileService: ProfileServiceProtocol, @unchecked Sendable {
    /// Singleton. Thread-safe durch `@unchecked Sendable` auf der Klasse.
    static let shared = ProfileService()

    private init() {}

    /// Liefert die aktuell eingeloggte User-ID aus dem AuthService.
    var currentUserId: UUID? {
        AuthService.shared.currentUser?.id
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        // 1. Lokal cachen (offline-first)
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.userProfile)

        // 2. Best-effort Sync auf Supabase user_metadata
        guard let jsonString = String(data: data, encoding: .utf8) else { return }
        let attributes = UserAttributes(data: [UserMetadataKey.profileJSON: .string(jsonString)])
        _ = try? await SupabaseService.shared.client.auth.update(user: attributes)
    }

    func loadProfile() async throws -> UserProfile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Lokaler Cache hat Vorrang
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.userProfile) {
            return try decoder.decode(UserProfile.self, from: data)
        }

        // 2. Fallback: user_metadata (z. B. nach App-Reinstall oder neuem Gerät)
        guard let user = AuthService.shared.currentUser,
              case .string(let jsonString) = user.userMetadata[UserMetadataKey.profileJSON],
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let profile = try decoder.decode(UserProfile.self, from: data)
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.userProfile)
        return profile
    }

    /// Löscht das lokal gecachte Profil aus den UserDefaults. Server-Account-
    /// Löschung erfordert Admin-Aktion (siehe PrivacyView, S3).
    func deleteLocalProfile() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.userProfile)
    }
}

enum ProfileServiceError: GermanLocalizedError {
    case encodingFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Dein Profil konnte nicht gespeichert werden."
        case .notAuthenticated:
            return "Du bist nicht angemeldet. Melde dich an, um dein Profil zu speichern."
        }
    }
}

private enum UserDefaultsKey {
    static let userProfile = "omina.userProfile"
}

private enum UserMetadataKey {
    static let profileJSON = "profile_json"
}