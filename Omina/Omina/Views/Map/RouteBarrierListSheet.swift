// RouteBarrierListSheet.swift
// Omina
//
// Listenansicht der Barrieren entlang der aktiven Route, sortiert in
// Laufrichtung – damit man vor dem Losfahren weiss, was auf einen zukommt.
// Jede Zeile zeigt Typ + Wert, die Position auf der Route und ob die
// Barriere fürs eigene Profil kritisch ist. Tippen öffnet das Detail-Sheet
// (BarrierDetailSheet), dort gibt es auch die Alternativroute für Barrieren,
// die heute nicht machbar sind.

import SwiftUI

struct RouteBarrierListSheet: View {
    let entries: [MapViewModel.RouteBarrierEntry]
    let profile: UserProfile
    /// Barrieren, die der User heute umgeht (Alternativroute aktiv).
    let avoidedBarrierIds: Set<UUID>
    /// Tap auf eine Zeile: Sheet schliessen und Barrieren-Detail öffnen.
    let onSelect: (Barrier) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Barrieren auf der Route")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var list: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry.barrier)
                    } label: {
                        BarrierRouteRow(
                            entry: entry,
                            isCritical: shouldWarn(barrier: entry.barrier, profile: profile),
                            isAvoided: avoidedBarrierIds.contains(entry.barrier.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Tippe eine Barriere an für Details – und für eine Alternativroute, wenn du sie heute nicht bewältigen kannst.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.Status.openIcon)
            Text("Keine bekannten Barrieren")
                .font(.headline)
            Text("Auf dieser Route sind aktuell keine Barrieren erfasst.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

/// Zeile einer Barriere in der Routen-Liste: Typ-Icon, Wert, Position auf
/// der Route und Status-Badge (kritisch/passierbar/wird umgangen).
private struct BarrierRouteRow: View {
    let entry: MapViewModel.RouteBarrierEntry
    let isCritical: Bool
    let isAvoided: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.barrier.type.tint)
                    .frame(width: 40, height: 40)
                Image(systemName: entry.barrier.type.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.barrier.type.localizedLabel)
                    .font(.subheadline.weight(.semibold))
                if let value = valueText {
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(positionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            statusBadge

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isAvoided {
            badge("Wird umgangen", fill: AppColor.Violet.v100, text: AppColor.accentPrimary)
        } else if isCritical {
            badge("Kritisch für dich", fill: AppColor.Status.blockedFill, text: AppColor.Status.blockedText)
        } else {
            badge("Passierbar", fill: AppColor.Status.openFill, text: AppColor.Status.openText)
        }
    }

    private func badge(_ label: String, fill: Color, text: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: - Formatierung

    private var valueText: String? {
        let barrier = entry.barrier
        switch barrier.type {
        case .steps:
            return barrier.value.map { "\(Int($0)) Stufen" }
        case .curb, .curbMissing:
            return barrier.value.map { "\(Int($0)) cm hoch" }
        case .incline:
            return barrier.value.map { "\(Int($0)) % Steigung" }
        case .narrow:
            return barrier.value.map { "\(Int($0)) cm Durchgang" }
        case .surface:
            return barrier.subtype.map(BarrierType.localizedSurface)
        case .temporary:
            return nil
        }
    }

    /// GPS-Toleranz, ab der eine Barriere hinter dem User als "passiert" gilt.
    private static let passedToleranceM = 10.0

    /// Position der Barriere relativ zum User ("in 120 m") bzw. ab Start,
    /// wenn der Standort unbekannt ist; bereits Passiertes wird benannt.
    private var positionText: String {
        if let ahead = entry.distanceAheadM {
            if ahead < -Self.passedToleranceM {
                return "Bereits passiert"
            }
            return "In \(distanceText(max(0, ahead)))"
        }
        return "Nach \(distanceText(entry.distanceFromStartM)) ab Start"
    }

    private func distanceText(_ meters: Double) -> String {
        DistanceFormatter.string(fromMeters: meters)
    }

    private var accessibilityText: String {
        var parts = [entry.barrier.type.localizedLabel]
        if let value = valueText { parts.append(value) }
        parts.append(positionText)
        if isAvoided {
            parts.append("wird umgangen")
        } else {
            parts.append(isCritical ? "kritisch für dich" : "passierbar")
        }
        return parts.joined(separator: ", ")
    }
}