// MapRoutePanel.swift
// Omina
//
// Bottom-Panel während der Navigation, Aufbau nach Entwurf: Kopfzeile mit
// Beenden links, «Route» mittig und der Wegbeschreibung als Liste rechts.
// Darunter Zielname, Ankunftszeit und Restdistanz in einer Zeile, dann der
// Fortschrittsbalken mit dem Pfeil an der aktuellen Position. Zuunterst das
// nächste Manöver und die Barrieren auf der Route, je als getönte Karte.
//
// Bei Ankunft (< 10 m Restweg) bleibt die Kopfzeile mit «Ziel erreicht» und
// dem Fertig-Knopf. Kopfzeile, Zusammenfassung und Balken teilt sich das
// Panel mit dem AR-Modus (ARRoutePanel).

import SwiftUI

struct MapRoutePanel: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    var maneuver: RouteManeuver? = nil
    /// Aktueller Schritt der Route – liefert die Strasse ("wo durch").
    var currentStep: RouteStep? = nil
    /// Öffnet die Turn-by-turn-Listenansicht; nil blendet den Listen-Button aus.
    var onShowSteps: (() -> Void)? = nil
    /// Barrieren im Korridor der aktiven Route (für die Zeile darunter).
    var barrierCount: Int = 0
    /// Davon fürs eigene Profil kritisch (shouldWarn).
    var criticalCount: Int = 0
    /// Öffnet die Barrieren-Liste; nil blendet die Zeile aus.
    var onShowBarriers: (() -> Void)? = nil
    let onStop: () -> Void

    private var hasArrived: Bool { progress?.hasArrived ?? false }

    var body: some View {
        VStack(spacing: AppMetrics.Space.m) {
            RoutePanelHeader(
                hasArrived: hasArrived,
                onStop: onStop,
                onShowSteps: hasArrived ? nil : onShowSteps
            )

            if hasArrived {
                arrivedLine
            } else {
                RouteSummaryRow(route: route, progress: progress)
                RouteProgressBar(route: route, progress: progress)

                maneuverCard

                if let onShowBarriers {
                    barrierCard(action: onShowBarriers)
                }
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.m)
        // Die Fläche läuft bis an den unteren Bildschirmrand durch (Entwurf):
        // Unter dem Panel bleibt kein Streifen Karte mehr stehen. Nur der
        // Hintergrund greift in den sicheren Bereich, der Inhalt bleibt über
        // dem Home-Indikator.
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: AppMetrics.Radius.sheet + AppMetrics.Space.s,
                topTrailingRadius: AppMetrics.Radius.sheet + AppMetrics.Space.s,
                style: .continuous
            )
            .fill(AppColor.surfaceOverlay)
            .shadow(color: AppColor.textBrand.opacity(0.2), radius: 12, y: -2)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Ankunft: eine Zeile statt Manöver und Balken.
    private var arrivedLine: some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.Status.openIcon)
                .frame(width: 44, height: 44)
                .background(AppColor.Status.openFill, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Ziel erreicht")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textBrand)
                Text(route.destinationName)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// Nächstes Manöver mit der Distanz bis dorthin.
    private var maneuverCard: some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: maneuver?.direction.symbolName ?? route.kind.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(AppColor.accentMuted, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(maneuver?.instruction ?? "Der Route folgen")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textBrand)
                    .lineLimit(2)
                if let street = currentStep?.streetName {
                    Text(street)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppMetrics.Space.s)

            if let distance = maneuverDistanceText {
                Text(distance)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(maneuverAccessibilityText)
    }

    private var maneuverDistanceText: String? {
        guard let meters = maneuver?.distanceM ?? currentStep?.distanceM else { return nil }
        return DistanceFormatter.string(fromMeters: meters)
    }

    private var maneuverAccessibilityText: String {
        var parts = [maneuver?.instruction ?? "Der Route folgen"]
        if let street = currentStep?.streetName { parts.append(street) }
        if let distance = maneuverDistanceText { parts.append("noch \(distance)") }
        return parts.joined(separator: ", ")
    }

    /// Barrieren auf der Route – Symbol und Text, nie allein die Farbe.
    private func barrierCard(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                Image(systemName: barrierCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(
                        barrierCount == 0
                            ? AppColor.Status.openIcon
                            : (criticalCount > 0 ? AppColor.Status.blockedIcon : AppColor.Status.limitedIcon)
                    )

                Text(barrierRowText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textBrand)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: AppMetrics.Space.s)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(AppMetrics.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
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

// MARK: - Geteilte Bausteine (Karte und AR)

/// Kopfzeile des Routen-Panels: Beenden links, Titel mittig, Wegbeschreibung
/// rechts – dieselbe Form wie die Sheet-Kopfzeilen.
struct RoutePanelHeader: View {
    let hasArrived: Bool
    let onStop: () -> Void
    var onShowSteps: (() -> Void)?

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            SheetCircleButton(
                symbol: hasArrived ? "checkmark" : "xmark",
                label: hasArrived ? "Navigation abschliessen" : "Navigation beenden",
                action: onStop
            )

            Spacer(minLength: 0)

            Text("Route")
                .font(AppTypography.title3)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let onShowSteps {
                SheetCircleButton(
                    symbol: "list.bullet",
                    label: "Wegbeschreibung als Liste",
                    action: onShowSteps
                )
            } else {
                Color.clear.frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
            }
        }
    }
}

/// Zielname, Ankunftszeit und Restdistanz nebeneinander.
struct RouteSummaryRow: View {
    let route: ActiveRoute
    let progress: RouteProgress?

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            Text(route.destinationName)
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(AppColor.textBrand)
                .lineLimit(1)

            Spacer(minLength: AppMetrics.Space.s)

            Text("Ankunft \(arrivalText)")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textBrand)
                .monospacedDigit()

            Spacer(minLength: AppMetrics.Space.s)

            Text(remainingDistanceText)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textBrand)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ziel \(route.destinationName), Ankunft \(arrivalText), noch \(remainingDistanceText)")
    }

    private var remainingDistanceText: String {
        DistanceFormatter.string(fromMeters: progress?.remainingDistanceM ?? route.totalDistanceM)
    }

    private var arrivalText: String {
        let seconds = progress?.remainingTimeS ?? route.expectedTravelTimeS
        return Date().addingTimeInterval(seconds)
            .formatted(.dateTime.locale(.appGerman).hour().minute())
    }
}

/// Fortschritt auf der Route: zurückgelegter Teil kräftig, der Rest blass,
/// dazwischen der Pfeil an der aktuellen Position.
struct RouteProgressBar: View {
    let route: ActiveRoute
    let progress: RouteProgress?

    /// Anteil des bereits zurückgelegten Wegs (0 … 1).
    private var fraction: Double {
        let total = route.totalDistanceM
        guard total > 0, let remaining = progress?.remainingDistanceM else { return 0 }
        return max(0, min(1, 1 - remaining / total))
    }

    var body: some View {
        GeometryReader { geo in
            let arrowWidth: CGFloat = 22
            let usable = max(0, geo.size.width - arrowWidth)
            let done = usable * fraction

            HStack(spacing: 0) {
                Capsule()
                    .fill(AppColor.accentPrimary)
                    .frame(width: done, height: 4)

                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: arrowWidth)

                Capsule()
                    .fill(AppColor.accentMuted)
                    .frame(width: max(0, usable - done), height: 4)
            }
            .frame(height: 20)
        }
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.3), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route zu \(Int(fraction * 100)) Prozent zurückgelegt")
    }
}