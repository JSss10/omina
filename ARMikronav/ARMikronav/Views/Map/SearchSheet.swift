// SearchSheet.swift
// ARMikronav
//
// Ortssuche als Medium-Sheet mit Grabber (Apple-Maps-Manier): oben das
// Suchfeld und die Kategorie-Chips, darunter im Ausgangszustand die letzten
// Orte und eine "In der Nähe"-Liste (POIs nach Distanz zum Standort). Sobald
// getippt oder eine Kategorie gewählt wird, erscheint die Ergebnisliste
// (sortiert nach Distanz, mit Zugänglichkeits-Status). Fokussiert man das
// Suchfeld, wächst das Sheet auf die volle Höhe. Tap auf einen Eintrag
// schliesst das Sheet und übergibt den POI an die Karte (zentrieren + Detail).

import SwiftUI

struct SearchSheet: View {
    @ObservedObject var viewModel: MapViewModel
    let onSelect: (POI) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recentDestinations = RecentDestinationsStore.shared
    @State private var query = ""
    @State private var results: [POI] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    /// Aktiver Kategorie-Chip (für die Hervorhebung); nil bei Freitext-Suche.
    @State private var activeChip: String?
    /// Sheet-Höhe: startet als Medium, wächst beim Tippen auf die volle Höhe.
    @State private var detent: PresentationDetent = .medium
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal)
                .padding(.top, 8)

            categoryFilters
                .padding(.vertical, 12)

            content
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Beim Fokussieren auf volle Höhe wachsen, damit die Tastatur die
        // Ergebnisliste nicht verdeckt.
        .onChange(of: searchFieldFocused) { _, focused in
            if focused { detent = .large }
        }
    }

    // MARK: - Inhalt (Ergebnisse oder Ausgangszustand)

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView()
                .padding(.top, 40)
            Spacer()
        } else if hasSearched && results.isEmpty {
            emptyState
            Spacer()
        } else if !results.isEmpty {
            resultsList
        } else {
            browseList
        }
    }

    // MARK: - Suchfeld & Kategorien

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Ort suchen…", text: $query)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    activeChip = nil
                    runSearch(query)
                }
            if !query.isEmpty {
                Button {
                    resetToBrowse()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Kategorie-Filter (Café, WC, Restaurant …) als antippbare Chips.
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POICategory.chipLabels, id: \.self) { chip in
                    let isActive = activeChip == chip
                    Button {
                        runCategory(chip)
                    } label: {
                        Label(chip, systemImage: POICategory.symbol(forChip: chip))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.systemGray6)),
                                in: Capsule()
                            )
                            .foregroundStyle(isActive ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(chip) suchen")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Ausgangszustand: Letzte Orte + In der Nähe

    /// Ohne aktive Suche: zuletzt angesteuerte Orte und die nächstgelegenen
    /// POIs als Liste mit Icon und Name.
    private var browseList: some View {
        List {
            if !recentPlaces.isEmpty {
                Section("Letzte Orte") {
                    ForEach(recentPlaces) { place in
                        Button {
                            select(place.poi)
                        } label: {
                            placeRow(
                                poi: place.poi,
                                leadingSymbol: "clock.arrow.circlepath",
                                subtitle: recentSubtitle(place)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let nearby = viewModel.nearbyPOIs()
            if !nearby.isEmpty {
                Section("In der Nähe") {
                    ForEach(nearby) { poi in
                        Button {
                            select(poi)
                        } label: {
                            placeRow(
                                poi: poi,
                                leadingSymbol: poi.categorySymbol,
                                subtitle: poi.address
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if recentPlaces.isEmpty && nearby.isEmpty {
                emptyBrowseState
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Listenzeile mit Icon, Name, Status und Distanz zum Standort.
    private func placeRow(poi: POI, leadingSymbol: String, subtitle: String?) -> some View {
        HStack(spacing: AppMetrics.Space.m) {
            ZStack {
                Circle()
                    .fill(AppColor.Violet.v100)
                    .frame(width: 40, height: 40)
                Image(systemName: leadingSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: poi.accessStatus.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(poi.accessStatus.tint)
                    Text(poi.accessStatus.shortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(viewModel.userDistanceText(to: poi))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(poi.name), \(poi.accessStatus.shortLabel), \(viewModel.userDistanceText(to: poi))")
        .accessibilityAddTraits(.isButton)
    }

    private var emptyBrowseState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Noch keine Orte in der Nähe geladen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    // MARK: - Ergebnisliste (Suche / Kategorie)

    private var resultsList: some View {
        List {
            Section {
                ForEach(results) { poi in
                    Button {
                        select(poi)
                    } label: {
                        resultRow(poi)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(results.count) Ergebnisse · nach Entfernung")
            }
        }
        .listStyle(.plain)
    }

    private func resultRow(_ poi: POI) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(poi.name)
                    .font(.body.weight(.semibold))
                if let address = poi.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: poi.accessStatus.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(poi.accessStatus.tint)
                    Text(poi.accessStatus.shortLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(viewModel.userDistanceText(to: poi))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    // Empty-State mit Handlungs-Hinweis.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Keine zugänglichen Orte für \u{201E}\(query)\u{201C} in der Nähe gefunden.")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Versuche einen anderen Suchbegriff oder vergrössere den Kartenausschnitt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }

    // MARK: - Letzte Orte (aufgelöst auf echte POIs)

    /// Ein zuletzt angesteuerter Ort samt dem passenden geladenen POI.
    private struct RecentPlace: Identifiable {
        let destination: RecentDestination
        let poi: POI
        var id: UUID { destination.id }
    }

    /// Letzte Navigationsziele, die sich auf einen bekannten Altstadt-POI
    /// auflösen lassen (damit die Auswahl im gewohnten POI-Detail landet).
    private var recentPlaces: [RecentPlace] {
        recentDestinations.destinations.compactMap { destination in
            viewModel.poi(named: destination.name)
                .map { RecentPlace(destination: destination, poi: $0) }
        }
    }

    private func recentSubtitle(_ place: RecentPlace) -> String {
        place.destination.visitedAt.formatted(.relative(presentation: .named).locale(.appGerman))
    }

    // MARK: - Aktionen

    private func select(_ poi: POI) {
        onSelect(poi)
        dismiss()
    }

    private func resetToBrowse() {
        query = ""
        results = []
        hasSearched = false
        activeChip = nil
    }

    private func runSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchFieldFocused = false
        isSearching = true
        hasSearched = false
        Task {
            results = await viewModel.searchPOIs(query: trimmed)
            isSearching = false
            hasSearched = true
        }
    }

    /// Kategorie-Chip getippt: filtert die für die Altstadt geladenen POIs
    /// client-seitig auf die exakten ginto-Kategorie-Keys des Chips
    /// (kein RPC) und übernimmt den Filter auch für die Karten-Marker.
    private func runCategory(_ chip: String) {
        if activeChip == chip {
            // Erneutes Tippen hebt den Filter auf.
            resetToBrowse()
            viewModel.setCategory(nil)
            return
        }
        activeChip = chip
        query = chip
        searchFieldFocused = false
        viewModel.setCategory(chip)
        results = viewModel.poisForCategory(chip)
        hasSearched = true
    }
}