// RoutesSheet.swift
// Omina
//
// Routenplanung vor dem Start: Verkehrsmittel, Start/Ziel und die
// Wegvarianten zur Auswahl. Start ist immer der eigene Standort – die
// Navigation läuft live von dort, ein anderer Ausgangspunkt ergäbe keine
// Turn-by-turn-Führung.
//
// Die Varianten kommen von MapKit (Fussgängergeometrie); den Unterschied
// macht für Rollstuhlnutzende nicht die Minutenzahl, sondern wie viele
// Barrieren im Korridor der jeweiligen Strecke liegen – deshalb steht die
// Barrierenzahl auf jeder Karte, kritische extra ausgewiesen.

import SwiftUI

/// Verkehrsmittel im Routen-Sheet. Bisher rechnet die App nur die
/// Rollstuhl-Route; ÖV, Blindenhund und Begleitung sind als kommende
/// Funktionen sichtbar, aber nicht wählbar.
enum RouteMode: String, CaseIterable, Identifiable {
    case wheelchair, transit, guideDog, companion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wheelchair: return "Rollstuhl"
        case .transit:    return "Öffentlicher Verkehr"
        case .guideDog:   return "Blindenhund"
        case .companion:  return "Begleitung"
        }
    }

    var symbol: String {
        switch self {
        case .wheelchair: return "figure.roll"
        case .transit:    return "tram.fill"
        case .guideDog:   return "dog.fill"
        case .companion:  return "figure.2"
        }
    }

    /// Nur die Rollstuhl-Route lässt sich heute berechnen.
    var isAvailable: Bool { self == .wheelchair }
}

struct RoutesSheet: View {
    @ObservedObject var viewModel: MapViewModel
    let profile: UserProfile
    /// Navigation gestartet – die Karte zeigt danach die ganze Strecke.
    let onRouteStarted: (ActiveRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationService = LocationService.shared

    @State private var mode: RouteMode = .wheelchair
    @State private var destination: POI?
    @State private var showingSearch = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Routen", onClose: { dismiss() }, onConfirm: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    modePicker
                    stopsCard
                    optionsSection
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
        .sheet(isPresented: $showingSearch) {
            SearchSheet(viewModel: viewModel) { poi in
                select(poi)
            }
            .trackScreen("routes_search")
        }
        .onDisappear { viewModel.clearRouteOptions() }
    }

    // MARK: - Verkehrsmittel

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            SegmentedBar(
                segments: RouteMode.allCases.map {
                    SegmentedBar<RouteMode>.Segment(
                        value: $0,
                        label: $0.label,
                        symbol: $0.symbol,
                        isEnabled: $0.isAvailable
                    )
                },
                selection: $mode
            )

            Text("Routen mit ÖV, Blindenhund und Begleitung folgen zu einem späteren Zeitpunkt.")
                .font(AppTypography.footnote)
                .foregroundColor(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Start, Ziel, Stopps

    /// Start, Ziel und Stopps als Kette: Die violette Linie verbindet die
    /// Symbole und zeigt, dass die Zeilen eine Route bilden (Entwurf).
    private var stopsCard: some View {
        VStack(spacing: 0) {
            stopRow(
                symbol: "location.fill",
                title: "Mein Standort",
                subtitle: locationService.currentLocation == nil
                    ? "Standort wird gesucht…"
                    : "Start der Route"
            )

            Button {
                showingSearch = true
            } label: {
                stopRow(
                    symbol: "mappin.and.ellipse",
                    title: destination?.name ?? "Ziel wählen",
                    subtitle: destination?.address,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(destination?.name ?? "Ziel wählen")
            .accessibilityHint("Öffnet die Ortssuche")

            stopRow(
                symbol: "plus",
                title: "Stopp hinzufügen",
                subtitle: "Noch nicht verfügbar",
                isEnabled: false,
                isLast: true
            )
        }
        .padding(AppMetrics.Space.m)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    private func stopRow(
        symbol: String,
        title: String,
        subtitle: String?,
        isEnabled: Bool = true,
        isLast: Bool = false,
        showsChevron: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.m) {
            VStack(spacing: 0) {
                SheetRowIcon(symbol: symbol, isEnabled: isEnabled, isFilled: true)

                if !isLast {
                    Rectangle()
                        .fill(AppColor.accentMuted)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 2)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AppMetrics.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textBrand)
                        if let subtitle {
                            Text(subtitle)
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(minHeight: 40)

                if !isLast {
                    Rectangle()
                        .fill(AppColor.borderDecorative)
                        .frame(height: 1)
                        .padding(.top, AppMetrics.Space.s)
                        .padding(.bottom, AppMetrics.Space.s)
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Wegvarianten

    @ViewBuilder
    private var optionsSection: some View {
        if viewModel.isLoadingRouteOptions {
            HStack(spacing: AppMetrics.Space.s) {
                ProgressView()
                Text("Wege werden berechnet…")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, AppMetrics.Space.m)
        } else if let error = viewModel.routeOptionsError {
            optionsError(error)
        } else if !viewModel.routeOptions.isEmpty {
            VStack(spacing: AppMetrics.Space.m) {
                ForEach(viewModel.routeOptions) { option in
                    optionCard(option)
                }
            }
        } else if destination == nil {
            Text("Wähle ein Ziel – danach stehen hier die Wege mit ihren Barrieren zur Auswahl.")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppMetrics.Space.s)
        }
    }

    private func optionsError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Keine Route gefunden")
                .font(AppTypography.headline)
                .foregroundColor(AppColor.textPrimary)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Erneut versuchen") {
                if let destination { load(for: destination) }
            }
            .buttonStyle(.appSecondary(fullWidth: false))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Eine Wegvariante: Dauer gross, darunter Ankunft und Länge, darunter
    /// die Barrieren auf dieser Strecke.
    private func optionCard(_ option: MapViewModel.RouteOption) -> some View {
        Button {
            start(option)
        } label: {
            HStack(spacing: AppMetrics.Space.m) {
                VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                    Text(durationText(option.route.expectedTravelTimeS))
                        .font(AppTypography.title2)
                        .foregroundColor(AppColor.textBrand)

                    Text("\(arrivalText(option.route.expectedTravelTimeS)) Ankunft | \(DistanceFormatter.string(fromMeters: option.route.totalDistanceM))")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColor.textSecondary)

                    barrierLine(option)
                }

                Spacer(minLength: AppMetrics.Space.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColor.accentPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppColor.accentMuted, in: Circle())
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: option))
        .accessibilityHint("Startet die Navigation auf diesem Weg")
        .accessibilityAddTraits(.isButton)
    }

    /// Barrieren auf der Strecke – vierfach codiert (Symbol + Text + Farbe),
    /// damit die Zeile auch ohne Farbwahrnehmung eindeutig bleibt.
    @ViewBuilder
    private func barrierLine(_ option: MapViewModel.RouteOption) -> some View {
        HStack(spacing: 6) {
            Image(systemName: option.barrierCount == 0
                  ? "checkmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(option.barrierCount == 0
                                 ? AppColor.Status.openIcon
                                 : AppColor.Status.limitedIcon)
            Text(barrierText(option))
                .font(AppTypography.footnote)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(.top, 2)
    }

    // MARK: - Texte

    private func barrierText(_ option: MapViewModel.RouteOption) -> String {
        guard option.barrierCount > 0 else {
            return "Keine Barrieren auf dieser Route"
        }
        let base = option.barrierCount == 1
            ? "1 Barriere auf dieser Route"
            : "\(option.barrierCount) Barrieren auf dieser Route"
        guard option.criticalCount > 0 else { return base }
        return base + " · \(option.criticalCount) für dich kritisch"
    }

    /// Fahrzeit im eigenen Tempo, gerundet auf Minuten.
    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private func arrivalText(_ seconds: TimeInterval) -> String {
        Date().addingTimeInterval(seconds)
            .formatted(.dateTime.locale(.appGerman).hour().minute())
    }

    private func accessibilityText(for option: MapViewModel.RouteOption) -> String {
        "\(durationText(option.route.expectedTravelTimeS)), Ankunft \(arrivalText(option.route.expectedTravelTimeS)), \(DistanceFormatter.string(fromMeters: option.route.totalDistanceM)), \(barrierText(option))"
    }

    // MARK: - Aktionen

    private func select(_ poi: POI) {
        destination = poi
        load(for: poi)
    }

    private func load(for poi: POI) {
        Task { await viewModel.loadRouteOptions(to: poi, profile: profile) }
    }

    private func start(_ option: MapViewModel.RouteOption) {
        guard let destination else { return }
        viewModel.startNavigation(with: option, to: destination, profile: profile)
        onRouteStarted(option.route)
        dismiss()
    }
}