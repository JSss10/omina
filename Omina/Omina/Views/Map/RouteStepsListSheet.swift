// RouteStepsListSheet.swift
// Omina
//
// Turn-by-turn-Listenansicht der aktiven Route: zeigt in Reihenfolge, wo und
// wann man wo hin muss – Manöver (Icon + Anweisung), die Strasse/den Weg, dem
// man folgt ("wo durch"), und die Distanz je Schritt. Der aktuell zurückgelegte
// Schritt ist hervorgehoben, bereits passierte sind gedämpft mit Häkchen. Oben
// eine Zusammenfassung mit Ziel-POI, Restzeit, Ankunftszeit und Restdistanz.
// Öffnet sich aus dem Navigations-Panel (MapRoutePanel) als Medium-Sheet.

import SwiftUI

struct RouteStepsListSheet: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    /// Index des Schritts, den der User gerade zurücklegt (Hervorhebung).
    let currentStepIndex: Int?

    var body: some View {
        NavigationStack {
            Group {
                if route.steps.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Wegbeschreibung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Liste

    private var list: some View {
        List {
            Section {
                ForEach(route.steps) { step in
                    RouteStepRow(step: step, state: state(for: step))
                }
            } header: {
                summaryHeader
            }
        }
        .listStyle(.plain)
    }

    /// Zusammenfassung über der Liste: Ziel, Restzeit, Ankunft, Restdistanz.
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(route.destinationName, systemImage: "mappin.circle.fill")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(remainingTimeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Ankunft \(arrivalText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(remainingDistanceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .textCase(nil)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ziel \(route.destinationName), noch \(remainingTimeText), Ankunft \(arrivalText), \(remainingDistanceText)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Keine Wegbeschreibung verfügbar")
                .font(.headline)
            Text("Für diese Route liegen keine einzelnen Schritte vor. Folge der violetten Linie auf der Karte.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
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

/// Eine Zeile der Turn-by-turn-Liste.
private struct RouteStepRow: View {
    enum State {
        case done
        case current
        case upcoming
    }

    let step: RouteStep
    let state: State

    var body: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instruction)
                    .font(.subheadline.weight(state == .current ? .bold : .semibold))
                    .foregroundStyle(state == .done ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppColor.textPrimary))
                    .lineLimit(2)
                if let way = step.wayText {
                    Text(way)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if step.maneuver != .arrive {
                Text(DistanceFormatter.string(fromMeters: step.distanceM))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(state == .current ? AppColor.accentPrimary : AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, state == .current ? 10 : 0)
        .background(
            state == .current
                ? AnyShapeStyle(AppColor.Violet.v50)
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .opacity(state == .done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Manöver-Icon im Kreis; erledigte Schritte zeigen ein Häkchen, der
    /// aktuelle Schritt ist im Akzentviolett gefüllt.
    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconFill)
                .frame(width: 38, height: 38)
            Image(systemName: state == .done ? "checkmark" : step.maneuver.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconForeground)
        }
    }

    private var iconFill: AnyShapeStyle {
        switch state {
        case .current: return AnyShapeStyle(AppColor.accentPrimary)
        case .done:    return AnyShapeStyle(AppColor.Status.openFill)
        case .upcoming: return AnyShapeStyle(AppColor.Violet.v100)
        }
    }

    private var iconForeground: AnyShapeStyle {
        switch state {
        case .current: return AnyShapeStyle(AppColor.onAccent)
        case .done:    return AnyShapeStyle(AppColor.Status.openIcon)
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