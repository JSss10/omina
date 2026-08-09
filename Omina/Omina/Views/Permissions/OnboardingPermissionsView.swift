// OnboardingPermissionsView.swift
// Omina
//
// Einmaliger Berechtigungs-Screen im Onboarding – direkt nach dem Datenschutz-
// Screen (ConsentView). Hier gibt die Person einmal die Einwilligung für
// Standort, Kamera und Mitteilungen; die eigentlichen Abfragen laufen über
// Apples System-Prompts. Danach wird dieser Screen nie wieder gezeigt: im
// laufenden Betrieb kommt höchstens noch Apples eigener System-Prompt zum Zug.

import SwiftUI
import AVFoundation
import CoreLocation
import UserNotifications

enum OnboardingPermissionsStore {
    private static let key = "omina.onboardingPermissionsDone"

    static var completed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Feldtest: zurücksetzen, damit die nächste Testperson auf dem gleichen
    /// Gerät die Berechtigungen erneut erteilt.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct OnboardingPermissionsView: View {
    let onFinished: () -> Void

    @StateObject private var locationService = LocationService.shared
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppMetrics.Space.m) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColor.accentPrimary)
                        .padding(.top, AppMetrics.Space.xxl)

                    Text("Zugriff erlauben")
                        .font(AppTypography.title1)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Damit Omina dich vor Barrieren warnen kann, brauchen wir einmalig deine Zustimmung. Du erteilst sie jetzt – später wirst du nicht mehr danach gefragt.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppMetrics.Space.s)

                    VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                        permissionRow(
                            icon: "location.fill",
                            title: "Standort",
                            detail: "Zeigt Barrieren in deiner Nähe. Keine Ortung im Hintergrund."
                        )
                        permissionRow(
                            icon: "camera.fill",
                            title: "Kamera",
                            detail: "Nur für die AR-Ansicht. Es werden keine Aufnahmen gespeichert."
                        )
                        permissionRow(
                            icon: "bell.badge.fill",
                            title: "Mitteilungen",
                            detail: "Warnen dich vorausschauend, bevor du eine Barriere erreichst."
                        )
                    }
                    .padding(.top, AppMetrics.Space.s)
                }
                .padding(.horizontal, AppMetrics.Space.l)
            }

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Button {
                requestAll()
            } label: {
                if isRequesting {
                    ProgressView()
                        .tint(AppColor.onAccent)
                } else {
                    Text("Erlauben")
                }
            }
            .buttonStyle(.appPrimary)
            .disabled(isRequesting)

            Button("Später erlauben") {
                finish()
            }
            .buttonStyle(.appQuiet(fullWidth: true))
            .disabled(isRequesting)
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.s)
        .padding(.bottom, AppMetrics.Space.l)
        .background(AppColor.backgroundPrimary)
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: AppMetrics.Space.xs / 2) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m - AppMetrics.Space.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                .fill(AppColor.surfaceRaised)
        )
    }

    // MARK: - Anfragen

    /// Kurze Pause zwischen zwei System-Dialogen, damit sie ruhig einer nach
    /// dem anderen erscheinen statt direkt hintereinander aufzupoppen.
    private static let pauseBetweenPrompts: Duration = .milliseconds(600)

    /// Fragt die drei System-Prompts der Reihe nach an. Wichtig: Jeder Schritt
    /// wartet, bis die Person im vorherigen Dialog geantwortet hat – erst dann
    /// erscheint der nächste. Dazwischen liegt eine kurze Verschnaufpause,
    /// damit die Dialoge schön langsam nacheinander kommen. Bereits erteilte
    /// oder abgelehnte Berechtigungen werden übersprungen (kein Dialog, keine
    /// Pause).
    private func requestAll() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            var didShowPrompt = false

            // 1. Standort – auf die Antwort warten, bevor es weitergeht.
            if locationService.authorizationStatus == .notDetermined {
                _ = await locationService.requestAuthorizationAsync()
                didShowPrompt = true
            }

            // 2. Kamera
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                if didShowPrompt { try? await Task.sleep(for: Self.pauseBetweenPrompts) }
                _ = await AVCaptureDevice.requestAccess(for: .video)
                didShowPrompt = true
            }

            // 3. Mitteilungen
            let notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
            if notificationStatus == .notDetermined {
                if didShowPrompt { try? await Task.sleep(for: Self.pauseBetweenPrompts) }
                await BarrierNotificationService.shared.requestAuthorization()
            }

            await MainActor.run { finish() }
        }
    }

    private func finish() {
        OnboardingPermissionsStore.markCompleted()
        // Mitteilungs-Flag mitziehen, damit später kein weiterer Prompt folgt.
        NotificationPermissionStore.markAsked()
        onFinished()
    }
}