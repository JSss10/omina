// BarrierNotificationService.swift
// Omina
//
// Liefert Barriere-Warnungen über Apples UserNotifications-Framework aus
// (System-Notification-UI statt eigenem In-App-Banner). Als Delegate sorgt
// der Service dafür, dass Mitteilungen auch im Vordergrund als Banner
// erscheinen; ein Tap auf die Mitteilung publiziert die Barrier-ID, damit
// die aktive View das Detail-Sheet öffnen kann.

import Foundation
import UserNotifications
import Combine

@MainActor
final class BarrierNotificationService: NSObject, ObservableObject {
    static let shared = BarrierNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Barrier-ID der zuletzt angetippten Mitteilung; Views setzen sie nach
    /// dem Öffnen des Detail-Sheets wieder auf nil zurück.
    @Published var tappedBarrierId: UUID?

    private let center = UNUserNotificationCenter.current()
    private static let threadIdentifier = "barrier-warnings"
    /// Fester Request-Identifier der "Keine Barrieren in der Nähe"-Mitteilung.
    private static let allClearIdentifier = "barrier-all-clear"

    private override init() {
        super.init()
        center.delegate = self
        refreshAuthorizationStatus()
    }

    /// Erzeugt den Singleton früh im App-Start, damit der Delegate gesetzt
    /// ist, bevor die erste Mitteilung eintrifft bzw. angetippt wird.
    static func activate() {
        _ = shared
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func refreshAuthorizationStatus() {
        Task {
            authorizationStatus = await center.notificationSettings().authorizationStatus
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorizationStatus = await center.notificationSettings().authorizationStatus
        return granted
    }

    /// Stellt die Warnung sofort als lokale Mitteilung zu. Die Barrier-ID
    /// dient als Request-Identifier, sodass wiederholte Aufrufe für dieselbe
    /// Barriere die bestehende Mitteilung ersetzen statt zu stapeln.
    func post(_ warning: BarrierWarning) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = warning.barrier.type.localizedLabel
        content.subtitle = "in \(Int(warning.distance)) m · \(warning.barrierValue)"
        content.body = warning.userLimit
        content.sound = NotificationSettingsStore.shared.settings.soundEnabled ? .default : nil
        content.interruptionLevel = .active
        content.threadIdentifier = Self.threadIdentifier
        content.userInfo = ["barrierId": warning.barrier.id.uuidString]

        let request = UNNotificationRequest(
            identifier: warning.barrier.id.uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// Entfernt die zugestellte Mitteilung, sobald die Barriere ausser
    /// Reichweite ist oder die Warnung dismissed wurde.
    func withdraw(barrierId: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [barrierId.uuidString])
    }

    /// Meldet "Keine Barrieren in der Nähe", wenn im Warn-Radius keine für
    /// das Profil relevante Barriere liegt. Fester Identifier, damit
    /// wiederholte Aufrufe die Mitteilung ersetzen statt zu stapeln.
    func postAllClear(radius: Double) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keine Barrieren in der Nähe"
        content.body = "Im Umkreis von \(Int(radius)) m gibt es keine für dein Profil relevanten Barrieren."
        content.sound = nil
        content.interruptionLevel = .passive
        content.threadIdentifier = Self.threadIdentifier

        let request = UNNotificationRequest(
            identifier: Self.allClearIdentifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// Zieht die "Keine Barrieren"-Mitteilung zurück, sobald wieder eine
    /// relevante Barriere in Reichweite ist.
    func withdrawAllClear() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.allClearIdentifier])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension BarrierNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let idString = response.notification.request.content.userInfo["barrierId"] as? String,
              let barrierId = UUID(uuidString: idString) else { return }
        await MainActor.run { tappedBarrierId = barrierId }
    }
}