// ErrorText.swift
// Omina
//
// Deutsche Fehlermeldungen für die Oberfläche. Supabase und URLSession melden
// ihre Fehler auf Englisch («User already registered», «The Internet connection
// appears to be offline»); solche Sätze dürfen nie im Screen landen. Diese
// Stelle übersetzt die bekannten Fälle und fängt alles Übrige mit einer
// verständlichen Ersatzmeldung ab.
//
// Views zeigen deshalb `ErrorText.message(for: error)` statt
// `error.localizedDescription`.

import Foundation

/// Kennzeichnet eigene Fehlertypen, deren `errorDescription` bereits deutsch
/// formuliert ist. Nur diese Beschreibungen werden unverändert angezeigt –
/// alles andere (Supabase, URLSession) läuft durch die Übersetzung, damit
/// keine englischen Sätze in der Oberfläche landen.
nonisolated protocol GermanLocalizedError: LocalizedError {}

// `nonisolated`, damit die Übersetzung auch aus nicht-isolierten Stellen
// (Repositories, Services) aufgerufen werden kann – das Projekt baut sonst mit
// MainActor als Standard-Isolation.
nonisolated enum ErrorText {

    /// Ersatzmeldung, wenn sich der Fehler nicht zuordnen lässt – bewusst ohne
    /// technische Angaben, dafür mit dem nächsten Schritt.
    static let fallback = "Da ist etwas schiefgelaufen. Bitte versuche es noch einmal."

    /// Deutsche Meldung zu einem Fehler. `context` steht vorangestellt (z. B.
    /// «Registrierung fehlgeschlagen»), wenn die Meldung allein nicht sagt,
    /// welcher Schritt betroffen ist.
    static func message(for error: Error, context: String? = nil) -> String {
        let text = translated(error)
        guard let context, !context.isEmpty else { return text }
        return "\(context): \(text)"
    }

    // MARK: - Übersetzung

    private static func translated(_ error: Error) -> String {
        // Eigene Fehlertypen beschreiben sich schon auf Deutsch.
        if let localized = error as? GermanLocalizedError, let description = localized.errorDescription {
            return description
        }
        if let urlError = error as? URLError {
            return networkMessage(urlError)
        }
        if let match = authMessage(in: haystack(for: error)) {
            return match
        }
        return fallback
    }

    /// Alles, worin die englische Serverantwort stecken kann: Bei den
    /// Supabase-Fehlern trägt teils nur die Debug-Beschreibung den Klartext.
    private static func haystack(for error: Error) -> String {
        "\(error.localizedDescription) \(String(describing: error))".lowercased()
    }

    /// Netzwerkfehler von URLSession.
    private static func networkMessage(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return "Keine Internetverbindung. Prüfe dein Netz und versuche es erneut."
        case .networkConnectionLost:
            return "Die Verbindung ist abgebrochen. Bitte versuche es erneut."
        case .timedOut:
            return "Der Server antwortet gerade nicht. Bitte versuche es erneut."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Der Server ist nicht erreichbar. Bitte versuche es später erneut."
        default:
            return "Die Verbindung ist fehlgeschlagen. Bitte versuche es erneut."
        }
    }

    /// Bekannte Meldungen der Supabase-Anmeldung. Die Reihenfolge zählt: Der
    /// erste passende Schlüssel gewinnt, spezifische Fälle stehen deshalb vor
    /// den allgemeinen.
    private static func authMessage(in haystack: String) -> String? {
        let rules: [(keys: [String], message: String)] = [
            (["already registered", "already been registered", "user_already_exists"],
             "Für diese E-Mail-Adresse gibt es schon ein Konto. Melde dich an oder setze dein Passwort zurück."),
            (["invalid login credentials", "invalid_credentials"],
             "E-Mail-Adresse oder Passwort stimmt nicht."),
            (["email not confirmed", "email_not_confirmed"],
             "Deine E-Mail-Adresse ist noch nicht bestätigt. Öffne den Link in der Bestätigungs-E-Mail."),
            (["new password should be different", "same_password"],
             "Das neue Passwort muss sich vom bisherigen unterscheiden."),
            (["password should be at least", "weak_password"],
             "Das Passwort ist zu kurz oder zu einfach."),
            (["unable to validate email address", "invalid email", "email_address_invalid"],
             "Diese E-Mail-Adresse ist ungültig."),
            (["rate limit", "too many requests", "over_request_rate_limit", "429"],
             "Zu viele Versuche. Warte einen Moment und versuche es dann erneut."),
            (["token has expired", "otp_expired", "invalid token", "token_expired"],
             "Der Code ist abgelaufen oder falsch. Fordere einen neuen an."),
            (["user not found", "user_not_found"],
             "Zu dieser E-Mail-Adresse gibt es kein Konto."),
            (["signups not allowed", "signup_disabled", "anonymous sign-ins are disabled",
              "anonymous_provider_disabled"],
             "Neue Konten sind derzeit nicht möglich. Bitte melde dich später erneut."),
            (["not authenticated", "jwt expired", "session_not_found", "no session"],
             "Deine Sitzung ist abgelaufen. Melde dich bitte erneut an."),
            (["offline", "internet connection appears to be offline", "network"],
             "Keine Internetverbindung. Prüfe dein Netz und versuche es erneut.")
        ]

        for rule in rules where rule.keys.contains(where: { haystack.contains($0) }) {
            return rule.message
        }
        return nil
    }
}