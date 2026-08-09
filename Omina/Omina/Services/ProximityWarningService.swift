// ProximityWarningService.swift
// Omina
//
// Überwacht Annäherung an warnpflichtige Barrieren im AR-Modus.
// Findet die nächstgelegene Barriere innerhalb `warningDistance`, die für das
// User-Profil `shouldWarn()` triggert, und publiziert ein BarrierWarning.
// Eine einmal dismissed Barriere wird unterdrückt, bis sie ausser Reichweite gerät
// und sich der User ihr erneut nähert. Neue Warnungen werden zusätzlich als
// lokale Mitteilung über den BarrierNotificationService zugestellt.

import Foundation
import CoreLocation
import Combine

@MainActor
final class ProximityWarningService: ObservableObject {
    @Published private(set) var activeWarning: BarrierWarning?

    private let injectedWarningDistance: CLLocationDistance?
    private var suppressedBarrierId: UUID?
    /// Barriere, für die aktuell eine System-Mitteilung zugestellt ist.
    private var notifiedBarrierId: UUID?
    /// True, solange die "Keine Barrieren in der Nähe"-Mitteilung zugestellt
    /// ist – verhindert wiederholte Zustellung im selben Zustand.
    private var allClearNotified = false

    /// Liest den Warn-Radius live aus den User-Settings, damit Änderungen im
    /// SettingsView ohne Re-Init wirksam werden.
    private var warningDistance: CLLocationDistance {
        injectedWarningDistance ?? NotificationSettingsStore.shared.settings.warningRadius
    }

    init() {
        self.injectedWarningDistance = nil
    }

    init(warningDistance: CLLocationDistance) {
        self.injectedWarningDistance = warningDistance
    }

    func evaluate(userLocation: CLLocation?, barriers: [Barrier], profile: UserProfile) {
        guard let userLocation else {
            setActiveWarning(nil)
            return
        }

        let candidates: [(barrier: Barrier, distance: CLLocationDistance)] = barriers
            .compactMap { barrier in
                let location = CLLocation(latitude: barrier.latitude, longitude: barrier.longitude)
                let distance = userLocation.distance(from: location)
                guard distance <= warningDistance else { return nil }
                guard shouldWarn(barrier: barrier, profile: profile) else { return nil }
                return (barrier, distance)
            }

        let inRangeIds = Set(candidates.map { $0.barrier.id })
        if let id = suppressedBarrierId, !inRangeIds.contains(id) {
            suppressedBarrierId = nil
        }

        // "Keine Barrieren in der Nähe" nur melden, wenn schon Daten geladen
        // sind (sonst würde beim App-Start vor dem ersten Load gemeldet).
        syncAllClearNotification(clear: candidates.isEmpty, dataLoaded: !barriers.isEmpty)

        guard let nearest = candidates.min(by: { $0.distance < $1.distance }) else {
            setActiveWarning(nil)
            return
        }

        if nearest.barrier.id == suppressedBarrierId {
            setActiveWarning(nil)
            return
        }

        setActiveWarning(generateWarning(
            barrier: nearest.barrier,
            profile: profile,
            distance: nearest.distance
        ))
    }

    func dismissCurrent() {
        suppressedBarrierId = activeWarning?.barrier.id
        setActiveWarning(nil)
    }

    // MARK: - System-Mitteilungen

    private func setActiveWarning(_ warning: BarrierWarning?) {
        activeWarning = warning
        syncSystemNotification(with: warning)
    }

    /// Stellt für eine neue Warnung eine lokale Mitteilung zu bzw. zieht sie
    /// zurück, sobald keine Warnung mehr aktiv ist. Pro Barriere wird nur
    /// einmal zugestellt, obwohl evaluate() bei jedem Location-Update läuft.
    private func syncSystemNotification(with warning: BarrierWarning?) {
        if let warning, NotificationSettingsStore.shared.settings.warningsEnabled {
            guard warning.barrier.id != notifiedBarrierId else { return }
            notifiedBarrierId = warning.barrier.id
            BarrierNotificationService.shared.post(warning)
        } else if let id = notifiedBarrierId {
            notifiedBarrierId = nil
            BarrierNotificationService.shared.withdraw(barrierId: id)
        }
    }

    /// Stellt beim Wechsel in den Zustand "keine relevante Barriere im
    /// Warn-Radius" einmalig eine Mitteilung zu und zieht sie zurück, sobald
    /// wieder eine Barriere in Reichweite ist.
    private func syncAllClearNotification(clear: Bool, dataLoaded: Bool) {
        guard NotificationSettingsStore.shared.settings.warningsEnabled else { return }

        if clear, dataLoaded {
            guard !allClearNotified else { return }
            allClearNotified = true
            BarrierNotificationService.shared.postAllClear(radius: warningDistance)
        } else if !clear, allClearNotified {
            allClearNotified = false
            BarrierNotificationService.shared.withdrawAllClear()
        }
    }
}