// RouteStepsListSheet.swift
// Omina
//
// Turn-by-turn-Listenansicht der aktiven Route, Aufbau nach Entwurf: Kopfzeile
// «Wegbeschreibung», darunter eine Zeile mit Ziel, Ankunft und Distanz, dann
// die Schritte in einer getönten Karte – Symbol, Anweisung und die Distanz
// je Schritt.
//
// Der Schritt, den man gerade zurücklegt, ist hervorgehoben; erledigte stehen
// gedämpft mit Häkchen. Öffnet sich aus dem Navigations-Panel (MapRoutePanel).

import SwiftUI

struct RouteStepsListSheet: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    /// Index des Schritts, den der User gerade zurücklegt (Hervorhebung).
    let currentStepIndex: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Wegbeschreibung", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
                    summaryRow

                    if route.steps.isEmpty {
                        emptyState
                    } else {
                        stepsCard
                    }
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.s)
                .padding(.bottom, AppMetrics.Space.xl)
            }
        }
        .background(AppColor.backgroundPrimary)
        .presentationBackground(AppColor.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Zusammenfassung

    /// Ziel, Ankunftszeit und Restdistanz nebeneinander (Entwurf).
    private var summaryRow: some View {
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
        .padding(.vertical, AppMetrics.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ziel \(route.destinationName), noch \(remainingTimeText), Ankunft \(arrivalText), \(remainingDistanceText)")
    }

    // MARK: - Schritte

    private var stepsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(route.steps.enumerated()), id: \.element.id) { index, step in
                RouteStepRow(step: step, state: state(for: step))

                if index < route.steps.count - 1 {
                    Rectangle()
                        .fill(AppColor.borderDecorative)
                        .frame(height: 1)
                        .padding(.leading, 44 + AppMetrics.Space.m + AppMetrics.Space.m)
                }
            }
        }
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    private var emptyState: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Keine Wegbeschreibung verfügbar")
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textBrand)
            Text("Für diese Route liegen keine einzelnen Schritte vor. Folge der violetten Linie auf der Karte.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppMetrics.Space.xl)
    }

    // MARK: - Zustand je Schritt

    private func state(for step: RouteStep) -> RouteStepRow.State {
        guard let current = currentStepIndex else { return .upcoming }
        if step.id < current { return .done }
        if step.id == current { return .current }
        return .upcoming
    }

    // MARK: - Formatierung

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
}

/// Eine Zeile der Turn-by-turn-Liste: Manöver-Symbol im Kreis, Anweisung und
/// die Distanz rechts.
private struct RouteStepRow: View {
    enum State {
        case done
        case current
        case upcoming
    }

    let step: RouteStep
    let state: State

    var body: some View {
        HStack(spacing: AppMetrics.Space.m) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instruction)
                    .font(AppTypography.body)
                    .foregroundStyle(state == .done ? AppColor.textSecondary : AppColor.textBrand)
                    .lineLimit(2)
                if let way = step.wayText {
                    Text(way)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppMetrics.Space.s)

            if step.maneuver != .arrive {
                Text(DistanceFormatter.string(fromMeters: step.distanceM))
                    .font(AppTypography.body)
                    .foregroundStyle(state == .current ? AppColor.accentPrimary : AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(AppMetrics.Space.m)
        .frame(minHeight: AppMetrics.Touch.primary)
        .background(
            state == .current
                ? AnyShapeStyle(AppColor.accentMuted.opacity(0.5))
                : AnyShapeStyle(Color.clear)
        )
        .opacity(state == .done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Manöver-Symbol im Kreis; erledigte Schritte zeigen ein Häkchen, der
    /// aktuelle Schritt ist im Akzentviolett gefüllt.
    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconFill)
                .frame(width: 44, height: 44)
            Image(systemName: state == .done ? "checkmark" : step.maneuver.symbolName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(iconForeground)
        }
        .accessibilityHidden(true)
    }

    private var iconFill: AnyShapeStyle {
        switch state {
        case .current:  return AnyShapeStyle(AppColor.accentPrimary)
        case .done:     return AnyShapeStyle(AppColor.Status.openFill)
        case .upcoming: return AnyShapeStyle(AppColor.accentMuted)
        }
    }

    private var iconForeground: AnyShapeStyle {
        switch state {
        case .current:  return AnyShapeStyle(AppColor.onAccent)
        case .done:     return AnyShapeStyle(AppColor.Status.openIcon)
        case .upcoming: return AnyShapeStyle(AppColor.accentPrimary)
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        switch state {
        case .done: parts.append("Erledigt")
        case .current: parts.append("Aktuell")
        case .upcoming: break
        }
        parts.append(step.instruction)
        if let way = step.wayText { parts.append(way) }
        if step.maneuver != .arrive {
            parts.append(DistanceFormatter.string(fromMeters: step.distanceM))
        }
        return parts.joined(separator: ", ")
    }
}