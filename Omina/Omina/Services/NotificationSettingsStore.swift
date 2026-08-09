// NotificationSettingsStore.swift
// Omina
//
// Hält die NotificationSettings als ObservableObject und persistiert sie
// in UserDefaults. Single Source of Truth für die Settings-UI (S2) und
// den ProximityWarningService.

import Foundation
import Combine

@MainActor
final class NotificationSettingsStore: ObservableObject {
    static let shared = NotificationSettingsStore()

    @Published var settings: NotificationSettings {
        didSet { persist() }
    }

    private let key = "omina.notificationSettings"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}