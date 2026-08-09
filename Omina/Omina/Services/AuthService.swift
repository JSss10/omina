// AuthService.swift
// Omina
//
// Wrapper um Supabase Auth - Sign Up, Sign In, Sign Out, Session Management

import Foundation
import Combine
import Supabase
import Auth

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User? = nil
    @Published var isLoading: Bool = true

    /// Steht auf true, solange nach einem Wiederherstellungs-Link ein neues
    /// Passwort gesetzt werden soll (Screen "Neues Passwort").
    @Published var isRecoveringPassword: Bool = false
    /// Meldung, wenn ein Deep Link nicht eingelöst werden konnte.
    @Published var deepLinkError: String? = nil


    private let client = SupabaseService.shared.client
    
    private init() {
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Session
    
    func checkSession() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let session = try await client.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
        } catch {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
    
    // MARK: - Sign Up
    
    /// Registrierung. Land und Telefonnummer sind freiwillig (Screen 0.2) und
    /// landen wie die Namen in den user_metadata – leere Angaben werden nicht
    /// mitgeschickt.
    func signUp(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        country: String = "",
        phone: String = ""
    ) async throws {
        var metadata: [String: AnyJSON] = [
            "first_name": .string(firstName),
            "last_name": .string(lastName)
        ]
        if !country.trimmingCharacters(in: .whitespaces).isEmpty {
            metadata["country"] = .string(country)
        }
        if !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            metadata["phone"] = .string(phone)
        }

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: metadata
        )

        self.currentUser = response.user
        self.isAuthenticated = response.session != nil
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        
        self.currentUser = session.user
        self.isAuthenticated = true
    }
    
    // MARK: - Anonymes Sign-in (Feldtest)

    /// Erstellt einen anonymen Supabase-User – für den Feldtest, damit
    /// Testpersonen ohne Registrierung starten können. Erfordert
    /// "Allow anonymous sign-ins" im Supabase-Dashboard.
    func signInAnonymously() async throws {
        let session = try await client.auth.signInAnonymously()
        self.currentUser = session.user
        self.isAuthenticated = true
    }

    // MARK: - Sign Out
    
    func signOut() async throws {
        try await client.auth.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    // MARK: - Password Reset

    /// Schickt den Wiederherstellungs-Link. `redirectTo` führt zurück in die
    /// App (omina://password-reset) – der Wert muss im Supabase-Dashboard
    /// unter Authentication → URL Configuration → Redirect URLs stehen.
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: AppConfig.passwordResetRedirectURL
        )
    }

    // MARK: - Deep Links

    /// Löst einen Deep Link ein. Der Link aus der Passwort-E-Mail bringt eine
    /// Sitzung mit: Supabase tauscht den Code darin gegen Tokens, danach darf
    /// das Passwort neu gesetzt werden.
    ///
    /// Ob es ein Wiederherstellungs-Link war, entscheidet die Adresse selbst
    /// (eigener Host bzw. `type=recovery`) – unabhängig davon, ob das Projekt
    /// im PKCE- oder im impliziten Flow läuft.
    func handleOpenURL(_ url: URL) async {
        guard url.scheme?.lowercased() == AppConfig.urlScheme else { return }

        let isRecovery = Self.isPasswordRecoveryLink(url)
        do {
            let session = try await client.auth.session(from: url)
            self.currentUser = session.user
            self.isAuthenticated = true
            self.deepLinkError = nil
            if isRecovery {
                self.isRecoveringPassword = true
            }
        } catch {
            self.deepLinkError = isRecovery
                ? "Der Link zum Zurücksetzen ist abgelaufen oder wurde schon benutzt. Fordere einen neuen an."
                : "Der Link konnte nicht geöffnet werden."
        }
    }

    /// Beendet den Wiederherstellungs-Ablauf (Passwort gesetzt oder abgebrochen).
    func finishPasswordRecovery() {
        isRecoveringPassword = false
    }

    /// Erkennt den Wiederherstellungs-Link am eigenen Host oder – falls das
    /// Projekt Tokens im Fragment liefert – an `type=recovery`.
    private static func isPasswordRecoveryLink(_ url: URL) -> Bool {
        if url.host?.lowercased() == AppConfig.passwordResetHost { return true }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if let fragment = components?.fragment,
           let fragmentItems = URLComponents(string: "?\(fragment)")?.queryItems {
            items += fragmentItems
        }
        return items.contains { $0.name == "type" && $0.value == "recovery" }
    }

    // MARK: - Neues Passwort setzen

    /// Setzt das Passwort der angemeldeten Sitzung neu (Screen "Neues
    /// Passwort"). Greift sowohl beim Ändern aus den Einstellungen als auch
    /// nach dem Wiederherstellungs-Link, der die Sitzung mitbringt.
    func updatePassword(_ newPassword: String) async throws {
        let user = try await client.auth.update(
            user: UserAttributes(password: newPassword)
        )
        self.currentUser = user
    }

    // MARK: - E-Mail-Bestätigung erneut senden

    func resendConfirmation(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup)
    }

    // MARK: - E-Mail-Bestätigung per Code

    /// Bestätigt das Konto mit dem 6-stelligen Code aus der
    /// Registrierungs-E-Mail (Alternative zum Link).
    func verifySignUpCode(email: String, code: String) async throws {
        let response = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .signup
        )
        self.currentUser = response.user
        self.isAuthenticated = response.session != nil
    }

    // MARK: - Anmeldung per Einmalcode (OTP)

    /// Sendet einen 6-stelligen Einmalcode an die angegebene Adresse.
    /// `shouldCreateUser: false` verhindert, dass dabei versehentlich
    /// ein neues Konto entsteht.
    func sendLoginCode(email: String) async throws {
        try await client.auth.signInWithOTP(
            email: email,
            shouldCreateUser: false
        )
    }

    /// Prüft den Einmalcode und meldet die Person an.
    func verifyLoginCode(email: String, code: String) async throws {
        let response = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .email
        )
        self.currentUser = response.user
        self.isAuthenticated = response.session != nil
    }
}