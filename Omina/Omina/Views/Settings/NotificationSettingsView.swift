// NotificationSettingsView.swift
// Omina
//
// Konfiguriert Warn-Radius und Verhalten der Proximity-Warnung. Die Warnungen
// werden als System-Mitteilungen (Apple UserNotifications) zugestellt; der
// Berechtigungsstatus wird hier angezeigt und ist über die iOS-Einstellungen
// nachholbar.

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var store = NotificationSettingsStore.shared
    @StateObject private var notificationService = BarrierNotificationService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Group {
                permissionSection
                warningsSection
                radiusSection
                soundSection
            }
            .appFormRowBackground()
        }
        .appFormBackground()
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            // Status neu laden, wenn der User aus den iOS-Einstellungen zurückkehrt.
            if newPhase == .active {
                notificationService.refreshAuthorizationStatus()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var permissionSection: some View {
        if !notificationService.isAuthorized {
            Section {
                if notificationService.authorizationStatus == .notDetermined {
                    Button("Mitteilungen erlauben") {
                        Task { await notificationService.requestAuthorization() }
                    }
                } else {
                    Button("iOS-Einstellungen öffnen") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("Ohne Mitteilungs-Berechtigung erscheinen Warnungen nur als Banner in der App, nicht über die iOS-Mitteilungen.")
            }
        }
    }

    private var warningsSection: some View {
        Section {
            Toggle("Warnungen anzeigen", isOn: $store.settings.warningsEnabled)
        } footer: {
            Text("Bei Annäherung an eine für dein Profil kritische Barriere erhältst du eine iOS-Mitteilung. Ist der Umkreis frei, meldet dir die App \u{201E}Keine Barrieren in der Nähe\u{201C}.")
        }
    }

    private var radiusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Warn-Radius")
                    Spacer()
                    Text("\(Int(store.settings.warningRadius)) m")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $store.settings.warningRadius,
                    in: NotificationSettings.minRadius...NotificationSettings.maxRadius,
                    step: NotificationSettings.radiusStep
                )
                .disabled(!store.settings.warningsEnabled)
                .accessibilityValue("\(Int(store.settings.warningRadius)) Meter")
            }
        } footer: {
            Text("Bestimmt, ab welcher Distanz zur Barriere die Warnung ausgelöst wird.")
        }
    }

    private var soundSection: some View {
        Section {
            Toggle("Sound", isOn: $store.settings.soundEnabled)
                .disabled(!store.settings.warningsEnabled)
        } footer: {
            Text("Spielt den Mitteilungston ab, wenn eine Warnung zugestellt wird.")
        }
    }
}