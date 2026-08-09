// NotificationSettings.swift
// Omina
//
// Benachrichtigungs-Einstellungen: Warn-Radius im AR-Modus, Master-Toggle für
// Warnbanner und Sound-Flag. Wird vom NotificationSettingsStore persistiert.

import Foundation

struct NotificationSettings: Codable, Equatable {
    var warningRadius: Double
    var warningsEnabled: Bool
    var soundEnabled: Bool

    static let `default` = NotificationSettings(
        warningRadius: AppConfig.approachWarningDistance,
        warningsEnabled: true,
        soundEnabled: true
    )

    static let minRadius: Double = 20
    static let maxRadius: Double = 100
    static let radiusStep: Double = 5
}