// NotificationPermissionView.swift
// Omina
//
// Persistenz-Flag für die Mitteilungs-Berechtigung. Es gibt keinen eigenen
// Erklärungs-Screen mehr: die Berechtigung wird einmalig – direkt nach dem
// Onboarding – über Apples System-Prompt angefragt (siehe OminaApp).
// Die inhaltliche Erklärung (wozu Standort/Kamera/Mitteilungen) erfolgt im
// Consent-Screen des Onboardings.

import Foundation

enum NotificationPermissionStore {
    private static let key = "omina.notificationPermissionAsked"

    static var wasAsked: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Feldtest: Flag zurücksetzen, damit die nächste Testperson auf dem
    /// gleichen Gerät den System-Prompt wieder erhält.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}