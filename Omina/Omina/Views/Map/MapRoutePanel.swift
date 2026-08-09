// MapRoutePanel.swift
// Omina
//
// Bottom-Panel während der Navigation in der Kartenansicht. Kopfzeile: das
// nächste Manöver (Icon + Anweisung), die aktuelle Strasse ("wo durch") und
// zwei Icon-Buttons – Wegbeschreibung als Liste (RouteStepsListSheet) und
// Stopp/Fertig (bewusst nur Icon, kein Text). Darunter die Zeitangabe
// (Restzeit + Ankunftszeit), die Restdistanz und der Ziel-POI, danach die
// Zeile mit der Anzahl Barrieren auf der Route (RouteBarrierListSheet). Bei
// Ankunft (< 10 m Restweg) bleibt nur die "Ziel erreicht"-Kopfzeile mit
// Fertig-Button. Die RouteInfoBar (unten in dieser Datei) wird weiterhin vom
// ARRoutePanel verwendet.

import SwiftUI

struct MapRoutePanel: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    var maneuver: RouteManeuver? = nil
    /// Aktueller Schritt der Route – liefert die Strasse ("wo durch") für die
    /// Kopfzeile. nil, wenn keine Schrittdaten vorliegen.
    var currentStep: RouteStep? = nil
    /// Öffnet die Turn-by-turn-Listenansicht; nil blendet den Listen-Button aus.
    var onShowSteps: (() -> Void)? = nil
    /// Barrieren im Korridor der aktiven Route (für die Zähler-Zeile).
    var barrierCount: Int = 0
    /// Davon fürs eigene Profil kritisch (shouldWarn).
    var criticalCount: Int = 0
    /// Öffnet die Barrieren-Liste; nil blendet die Zeile aus.
    var onShowBarriers: (() -> Void)? = nil
    let onStop: () -> Void

    private var hasArrived: Bool { progress?.hasArrived ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !hasArrived {
                Divider()
                    .padding(.vertical, 10)
                infoSection

                if let onShowBarriers {
                    Divider()
                        .padding(.vertical, 10)
                    barrierRow(action: onShowBarriers)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 6)
    }

    // MARK: - Kopfzeile (nächstes Manöver + Aktionen)

    /// Kopfzeile: Manöver-Icon, Anweisung, aktuelle Strasse ("wo durch") sowie
    /// die Icon-Buttons für die Listenansicht und den Stopp/Fertig-Knopf –
    /// bewusst nur Icons, kein Text (Feldtest-Rückmeldung).
    private var header: some View {
        HStack(spacing: 14) {
            maneuverIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(headlineText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let onShowSteps, !hasArrived {
                iconButton(
                    systemImage: "list.bullet",
                    tint: AppColor.accentPrimary,
                    accessibilityLabel: "Wegbeschreibung als Liste",
                    action: onShowSteps
                )
            }
            stopButton
        }
        .accessibilityElement(children: .contain)
    }

    private var maneuverIcon: some View {
        ZStack {
            Circle()
                .fill(hasArrived ? AppColor.Status.openFill : AppColor.accentPrimary)
                .frame(width: 48, height: 48)
            Image(systemName: routeIcon)
                .font(.title2.weight(.bold))
                .foregroundStyle(hasArrived ? AppColor.Status.openIcon : AppColor.onAccent)
        }
        .accessibilityHidden(true)
    }

    /// Stopp (läuft) bzw. Fertig (am Ziel) – reiner Icon-Button. Am Ziel
    /// prominent grün gefüllt, sonst neutral, damit er nicht mit dem
    /// Akzent-Manöver-Icon konkurriert.
    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: hasArrived ? "checkmark" : "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(hasArrived ? AppColor.onAccent : AppColor.textPrimary)
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .background(
                    hasArrived
                        ? AnyShapeStyle(AppColor.Status.openIcon)
                        : AnyShapeStyle(Color(.secondarySystemFill)),
                    in: Circle()
                )
        }
        .accessibilityLabel(hasArrived ? "Navigation abschliessen" : "Navigation beenden")
    }

    private func iconButton(
        systemImage: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var routeIcon: String {
        if hasArrived { return "checkmark" }
        if let maneuver { return maneuver.direction.symbolName }
        return route.kind.symbolName
    }

    private var headlineText: String {
        if hasArrived { return "Ziel erreicht" }
        return maneuver?.instruction ?? route.destinationName
    }

    /// Kopf-Untertitel: am Ziel der Zielname, sonst die Strasse, auf der man
    /// gerade unterwegs ist ("wo durch").
    private var headerSubtitle: String? {
        if hasArrived { return route.destinationName }
        return currentStep?.streetName
    }

    // MARK: - Info (Zeit, Distanz, Ankunft, Ziel-POI)

    /// Zeitangabe (Restzeit + Ankunftszeit), Restdistanz und Ziel-POI – so ist
    /// «wann» und «wohin» auf einen Blick ersichtlich.
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                Text(remainingTimeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                Text("· \(remainingDistanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Ankunft \(arrivalText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            Label(route.destinationName, systemImage: "mappin.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Noch \(remainingTimeText), \(remainingDistanceText), Ankunft \(arrivalText), Ziel \(route.destinationName)")
    }

    private var remainingTimeText: String {
        let seconds = progress?.remainingTimeS ?? route.expectedTravelTimeS
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return "\(minutes) min"
    }

    private var remainingDistanceText: String {
        DistanceFormatter.string(fromMeters: progress?.remainingDistanceM ?? route.totalDistanceM)
    }

    private var arrivalText: String {
        let seconds = progress?.remainingTimeS ?? route.expectedTravelTimeS
        return Date().addingTimeInterval(seconds)
            .formatted(.dateTime.locale(.appGerman).hour().minute())
    }

    /// Zeile "X Barrieren auf der Route" mit Warnfarbe, sobald mindestens
    /// eine Barriere fürs Profil kritisch ist.
    private func barrierRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: barrierCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        barrierCount == 0
                            ? AppColor.Status.openIcon
                            : (criticalCount > 0 ? AppColor.Status.blockedIcon : AppColor.Status.limitedIcon)
                    )

                Text(barrierRowText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(barrierRowText), Liste öffnen")
    }

    private var barrierRowText: String {
        if barrierCount == 0 {
            return "Keine bekannten Barrieren auf der Route"
        }
        let base = barrierCount == 1
            ? "1 Barriere auf der Route"
            : "\(barrierCount) Barrieren auf der Route"
        guard criticalCount > 0 else { return base }
        return "\(base) · \(criticalCount) kritisch"
    }
}

/// Infozeile einer aktiven Route: Richtungspfeil mit Abbiege-Anweisung
/// (geradeaus/links/rechts), Zielname, Restzeit/-distanz und Stop-Button,
/// mit "Ziel erreicht"-Zustand bei Ankunft. Die Art der Route (Rollstuhl-
/// Routing oder Fussgänger-Fallback) zeigt nur noch das Symbol im
/// Manöver-Kreis; die Barrieren entlang der Strecke werden in beiden Fällen
/// ausgewiesen, ein zusätzlicher Warnhinweis wäre also irreführend.
struct RouteInfoBar: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    var maneuver: RouteManeuver? = nil
    let onStop: () -> Void

    private var hasArrived: Bool {
        progress?.hasArrived ?? false
    }

    private var routeIcon: String {
        if hasArrived { return "checkmark.circle.fill" }
        if let maneuver { return maneuver.direction.symbolName }
        return route.kind.symbolName
    }

    private var headlineText: String {
        if hasArrived { return "Ziel erreicht" }
        return maneuver?.instruction ?? route.destinationName
    }

    private var subheadlineText: String {
        if hasArrived { return route.destinationName }
        guard maneuver != nil else { return progressText }
        return "\(route.destinationName) · \(progressText)"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Abbiege-Symbol prominent im Akzentkreis (Apple-Maps-Manier),
            // damit «wo man durch muss» sofort erfassbar ist.
            ZStack {
                Circle()
                    .fill(hasArrived ? AppColor.Status.openFill : AppColor.accentPrimary)
                    .frame(width: 48, height: 48)
                Image(systemName: routeIcon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(hasArrived ? AppColor.Status.openIcon : AppColor.onAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headlineText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(subheadlineText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Button(action: onStop) {
                Text(hasArrived ? "Fertig" : "Stopp")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(AppColor.accentPrimary, in: Capsule())
            }
            .accessibilityLabel(hasArrived ? "Navigation abschliessen" : "Navigation beenden")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Formatierung

    private var progressText: String {
        let distance = progress?.remainingDistanceM ?? route.totalDistanceM
        let time = progress?.remainingTimeS ?? route.expectedTravelTimeS
        return "\(minutesText(time)) · \(distanceText(distance))"
    }

    private func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return "\(minutes) min"
    }

    private func distanceText(_ meters: Double) -> String {
        DistanceFormatter.string(fromMeters: meters)
    }

    private var accessibilitySummary: String {
        if hasArrived {
            return "Ziel erreicht: \(route.destinationName)"
        }
        var summary = "Navigation zu \(route.destinationName), noch \(progressText)"
        if let maneuver {
            summary = "\(maneuver.instruction). \(summary)"
        }
        return summary
    }
}