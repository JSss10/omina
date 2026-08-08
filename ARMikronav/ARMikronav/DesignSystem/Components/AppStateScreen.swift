// AppStateScreen.swift
// ARMikronav
//
// Ganzflächiger Zustands-Screen (Figma: States "Standort", "Route",
// "Synchronisierung", "Kamera"). Violett getönte Fläche, zentriertes Symbol,
// darunter Titel und erklärender Text – und, wo es einen Weg aus dem Zustand
// heraus gibt, die passende Aktion.
//
// Die vier Zustände des Figma-Sets liegen unten als fertige Presets bereit,
// damit Titel, Text und Symbol an einer Stelle gepflegt werden.

import SwiftUI

struct AppStateScreen: View {

    /// Beschriftete Aktion unter dem Text (z. B. "Einstellungen öffnen").
    struct Action {
        let title: String
        let perform: () -> Void

        init(_ title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    /// SF-Symbol über dem Text.
    let symbol: String
    let title: String
    let message: String
    /// Ladezustand: Das Symbol dreht sich. Bei "Bewegung reduzieren" bleibt es
    /// stehen (WCAG 2.3.3), der Text trägt die Information ohnehin allein.
    var isSpinning: Bool = false
    var primaryAction: Action?
    var secondaryAction: Action?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        // Der Inhalt steht mittig; wächst er über die Fläche hinaus (grosse
        // Dynamic-Type-Stufen bis AX5), wird er scrollbar statt abgeschnitten.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppColor.backgroundMuted.ignoresSafeArea())
    }

    // MARK: - Bausteine

    private var content: some View {
        VStack(spacing: AppMetrics.Space.l) {
            icon

            VStack(spacing: AppMetrics.Space.s) {
                Text(title)
                    .font(AppTypography.title2)
                    .foregroundColor(AppColor.textPrimary)
                    // Überschrift des Zustands: VoiceOver springt per Rotor
                    // direkt hierher, der Text darunter erklärt ihn.
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

            if primaryAction != nil || secondaryAction != nil {
                actions
                    .padding(.top, AppMetrics.Space.s)
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.vertical, AppMetrics.Space.xl)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 40, weight: .regular))
            .foregroundColor(AppColor.accentPrimary)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
            .onAppear {
                guard isSpinning, !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }

    private var actions: some View {
        VStack(spacing: AppMetrics.Touch.spacing) {
            if let primaryAction {
                Button(primaryAction.title, action: primaryAction.perform)
                    .buttonStyle(.appPrimary)
            }
            if let secondaryAction {
                Button(secondaryAction.title, action: secondaryAction.perform)
                    .buttonStyle(.appSecondary)
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Presets (Figma-Set)

extension AppStateScreen {

    /// Standort gesperrt: Ohne Freigabe gibt es weder Barrieren in der Nähe
    /// noch eine Route. Der zweite Weg lässt die Karte trotzdem zu.
    static func locationUnavailable(
        onOpenSettings: @escaping () -> Void = { AppStateScreen.openSystemSettings() },
        onShowMapAnyway: (() -> Void)? = nil
    ) -> AppStateScreen {
        AppStateScreen(
            symbol: "mappin.slash",
            title: "Standort nicht freigegeben",
            message: "Ohne deinen Standort lassen sich Barrieren in der Nähe und Routen nicht anzeigen. Gib den Zugriff in den Einstellungen frei.",
            primaryAction: Action("Einstellungen öffnen", perform: onOpenSettings),
            secondaryAction: onShowMapAnyway.map { Action("Karte trotzdem ansehen", perform: $0) }
        )
    }

    /// Kein brauchbarer GPS-Fix – der AR-Modus braucht den genauen Standort,
    /// um Barrieren an der richtigen Stelle im Kamerabild zu verankern.
    static func locationSignalWeak(onBack: @escaping () -> Void) -> AppStateScreen {
        AppStateScreen(
            symbol: "mappin.slash",
            title: "Kein GPS-Signal",
            message: "Der AR-Modus braucht deinen genauen Standort. Zwischen hohen Häusern dauert der Empfang länger – gehe für besseren Empfang ins Freie.",
            primaryAction: Action("Zurück zur Karte", perform: onBack)
        )
    }

    /// Route konnte nicht berechnet werden. `reason` ist die konkrete Meldung
    /// aus dem Routing (Standort ungenau, Netzwerk, kein Weg gefunden).
    static func routeUnavailable(
        reason: String? = nil,
        onRetry: (() -> Void)? = nil,
        onBack: @escaping () -> Void
    ) -> AppStateScreen {
        // Gibt es einen zweiten Versuch, ist er die Hauptaktion; sonst führt
        // der Rückweg zur Karte als Hauptaktion aus dem Zustand heraus.
        let back = Action("Zurück zur Karte", perform: onBack)
        return AppStateScreen(
            symbol: "paperplane.slash",
            title: "Keine Route gefunden",
            message: reason ?? "Zu diesem Ziel liess sich gerade kein Weg berechnen. Versuche es erneut oder wähle ein anderes Ziel.",
            primaryAction: onRetry.map { Action("Erneut versuchen", perform: $0) } ?? back,
            secondaryAction: onRetry == nil ? nil : back
        )
    }

    /// Datenabgleich mit dem Konto bzw. der Altstadt-Datenbank.
    static func syncing(
        title: String = "Daten werden geladen",
        message: String = "Barrieren und Orte in der Altstadt werden abgeglichen. Das dauert nur einen Moment."
    ) -> AppStateScreen {
        AppStateScreen(
            symbol: "arrow.triangle.2.circlepath",
            title: title,
            message: message,
            isSpinning: true
        )
    }

    /// Kamera-Zugriff verweigert – der AR-Modus braucht das Kamerabild.
    static func cameraAccessDenied(
        onOpenSettings: @escaping () -> Void = { AppStateScreen.openSystemSettings() },
        onBack: @escaping () -> Void
    ) -> AppStateScreen {
        AppStateScreen(
            symbol: "camera.viewfinder",
            title: "Kein Kamerazugriff",
            message: "Der AR-Modus zeigt Barrieren im Kamerabild. Erlaube den Kamerazugriff in den Einstellungen, um ihn zu nutzen.",
            primaryAction: Action("Einstellungen öffnen", perform: onOpenSettings),
            secondaryAction: Action("Zurück zur Karte", perform: onBack)
        )
    }

    /// AR-Session lässt sich nicht aufbauen (ARGeo nicht verfügbar, Session-
    /// Fehler, Lokalisierung fehlgeschlagen). Die Karte bleibt der Rückweg.
    static func arUnavailable(
        reason: String,
        onBack: @escaping () -> Void
    ) -> AppStateScreen {
        AppStateScreen(
            symbol: "camera.viewfinder",
            title: "AR nicht verfügbar",
            message: reason,
            primaryAction: Action("Zurück zur Karte", perform: onBack),
            secondaryAction: Action("Einstellungen öffnen") { AppStateScreen.openSystemSettings() }
        )
    }

    /// Wartezustand, während Apples Kamera-Dialog beantwortet wird.
    static func cameraPreparing() -> AppStateScreen {
        AppStateScreen(
            symbol: "camera.viewfinder",
            title: "Kamera wird vorbereitet",
            message: "Bestätige den Kamerazugriff, damit der AR-Modus mit dem Kamerabild starten kann."
        )
    }

    /// Öffnet die App-Einstellungen im System (Standort, Kamera, Mitteilungen).
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            UIApplication.shared.open(url)
        }
    }
}

#Preview("Standort") {
    AppStateScreen.locationUnavailable(onShowMapAnyway: {})
}

#Preview("Route") {
    AppStateScreen.routeUnavailable(onRetry: {}, onBack: {})
}

#Preview("Synchronisierung") {
    AppStateScreen.syncing()
}

#Preview("Kamera") {
    AppStateScreen.cameraAccessDenied(onBack: {})
}