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
    
    func signUp(email: String, password: String, firstName: String, lastName: String) async throws {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "first_name": .string(firstName),
                "last_name": .string(lastName)
            ]
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

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
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