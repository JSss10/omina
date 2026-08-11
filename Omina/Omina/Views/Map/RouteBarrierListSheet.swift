// RouteBarrierListSheet.swift
// Omina
//
// Listenansicht der Barrieren entlang der aktiven Route, sortiert in
// Laufrichtung – damit man vor dem Losfahren weiss, was auf einen zukommt.
// Aufbau nach Entwurf: Kopfzeile «Barrieren auf der Route», darunter je
// Barriere eine getönte Karte mit Symbolkreis, Typ, Position und dem Status
// fürs eigene Profil.
//
// Tippen öffnet das Detail-Sheet (BarrierDetailSheet), dort gibt es auch die
// Alternativroute für Barrieren, die heute nicht machbar sind.

import SwiftUI

struct RouteBarrierListSheet: View {
    let entries: [MapViewModel.RouteBarrierEntry]
    let profile: UserProfile
    /// Barrieren, die der User heute umgeht (Alternativroute aktiv).
    let avoidedBarrierIds: Set<UUID>
    /// Tap auf eine Zeile: Sheet schliessen und Barrieren-Detail öffnen.
    let onSelect: (Barrier) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Barrieren auf der Route", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    if entries.isEmpty {
                        emptyState
                    } else {
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

                        Text("Tippe eine Barriere an für Details – und für eine Alternativroute, wenn du sie heute nicht bewältigen kannst.")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, AppMetrics.Space.s)
                    }
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.s)
                .padding(.bottom, AppMetrics.Space.xl)
            }
        }
        .background(AppColor.surfaceOverlay)
        .presentationBackground(AppColor.surfaceOverlay)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.Status.openIcon)
            Text("Keine bekannten Barrieren")
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textBrand)
            Text("Auf dieser Route sind aktuell keine Barrieren erfasst.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppMetrics.Space.xl)
    }
}

/// Karte einer Barriere in der Routen-Liste: Symbolkreis, Typ, Wert samt
/// Position und der Status fürs eigene Profil – Symbol und Text, nie nur Farbe.
private struct BarrierRouteRow: View {
    let entry: MapViewModel.RouteBarrierEntry
    let isCritical: Bool
    let isAvoided: Bool

    var body: some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: entry.barrier.type.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 56, height: 56)
                .background(AppColor.accentMuted, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.barrier.type.localizedLabel)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textBrand)

                Text(detailLine)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()

                HStack(spacing: AppMetrics.Space.s - 2) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusTint)
                    Text(statusLabel)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: AppMetrics.Space.s)

            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.textBrand)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Wert und Position in einer Zeile, z. B. «Kopfsteinpflaster in 200 m».
    private var detailLine: String {
        let position = positionText
        guard let value = valueText else { return position }
        return "\(value) \(position.lowercased())"
    }

    private var statusSymbol: String {
        if isAvoided { return "arrow.triangle.branch" }
        return isCritical ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if isAvoided { return AppColor.accentPrimary }
        return isCritical ? AppColor.Status.blockedIcon : AppColor.Status.openIcon
    }

    private var statusLabel: String {
        if isAvoided { return "Wird umgangen" }
        return isCritical ? "Kritisch für dich" : "Passierbar für dich"
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
        var parts = [entry.barrier.type.localizedLabel, detailLine, statusLabel]
        parts.removeAll { $0.isEmpty }
        return parts.joined(separator: ", ")
    }
}