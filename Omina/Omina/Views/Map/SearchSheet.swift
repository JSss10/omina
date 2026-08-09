// SearchSheet.swift
// Omina
//
// Ortssuche als Medium-Sheet mit Grabber: oben das Suchfeld mit dem
// Filter-Icon, darunter die Kategorien als runde Icon-Buttons und im
// Ausgangszustand die gespeicherten Orte, die letzten Ziele und die Orte in
// der Nähe. Sobald getippt oder eine Kategorie gewählt wird, erscheint die
// Ergebnisliste (nach Distanz sortiert, mit Zugänglichkeits-Status).
// Fokussiert man das Suchfeld, wächst das Sheet auf die volle Höhe.
// Tap auf einen Eintrag schliesst das Sheet und übergibt den POI an die
// Karte (zentrieren + Detail).

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
    /// Gespeicherte Orte des Users – im Ausgangszustand ganz oben gelistet,
    /// damit man sie direkt aus der Suche ansteuern kann.
    @State private var savedPlaces: [SavedPlace] = []
    /// Aktiver Kategorie-Chip (für die Hervorhebung); nil bei Freitext-Suche.
    @State private var activeChip: String?
    /// Sheet-Höhe: startet als Medium, wächst beim Tippen auf die volle Höhe.
    @State private var detent: PresentationDetent = .medium
    /// Filter-Sheet (Sichtbarkeit von Orten/Barrieren + Barrieretypen) – direkt
    /// neben der Suchleiste statt in den Karteneinstellungen.
    @State private var showingFilter = false
    @FocusState private var searchFieldFocused: Bool

    /// Ein Eintrag der Listen: derselbe Zeilenaufbau für gespeicherte Orte,
    /// letzte Ziele, Orte in der Nähe und Suchergebnisse.
    private struct PlaceEntry: Identifiable {
        let id: String
        let poi: POI
        let symbol: String
        let subtitle: String?
    }

    var body: some View {
        VStack(spacing: AppMetrics.Space.m) {
            // Suchfeld und – direkt rechts daneben – der Filter-Button für die
            // Barrieretypen und die Sichtbarkeit von Orten/Barrieren.
            HStack(spacing: 12) {
                searchField
                filterButton
            }
            .padding(.horizontal, AppMetrics.Space.l)
            // Mehr Luft zwischen Grabber und Suchfeld.
            .padding(.top, 20)

            categoryFilters

            content
        }
        .background(AppColor.backgroundPrimary)
        .presentationBackground(AppColor.backgroundPrimary)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Beim Fokussieren auf volle Höhe wachsen, damit die Tastatur die
        // Ergebnisliste nicht verdeckt.
        .onChange(of: searchFieldFocused) { _, focused in
            if focused { detent = .large }
        }
        .task { await loadSavedPlaces() }
        .sheet(isPresented: $showingFilter) {
            FilterSheet(viewModel: viewModel)
                .trackScreen("filter")
        }
    }

    /// Icon-Button rechts neben der Suchleiste: öffnet das Filter-Sheet.
    /// Hebt sich (Akzent-Füllung) hervor, sobald ein Filter aktiv ist –
    /// Orte/Barrieren ausgeblendet oder nicht alle Barrieretypen sichtbar.
    private var filterButton: some View {
        Button {
            showingFilter = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filtersActive ? AppColor.onAccent : AppColor.accentPrimary)
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .background(
                    filtersActive
                        ? AnyShapeStyle(AppColor.accentPrimary)
                        : AnyShapeStyle(AppColor.surfaceTinted),
                    in: Circle()
                )
        }
        .accessibilityLabel("Filter")
        .accessibilityAddTraits(filtersActive ? .isSelected : [])
    }

    /// Ob aktuell ein Filter greift (für die Hervorhebung des Filter-Buttons).
    private var filtersActive: Bool {
        !viewModel.poisVisible
            || !viewModel.barriersVisible
            || viewModel.filterState.enabledTypes.count != BarrierType.allCases.count
    }

    // MARK: - Inhalt (Ergebnisse oder Ausgangszustand)

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView()
                .padding(.top, AppMetrics.Space.xxl)
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
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
            TextField("Suchst du nach etwas Bestimmten?", text: $query)
                .font(AppTypography.body)
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
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: AppMetrics.Touch.minimum)
        .background(AppColor.surfaceTinted, in: Capsule())
    }

    /// Kategorie-Filter (Restaurant, Café, WC …) als kreisförmige Icon-Buttons
    /// mit Titel darunter.
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppMetrics.Space.m) {
                ForEach(POICategory.chipLabels, id: \.self) { chip in
                    categoryChip(chip)
                }
            }
            .padding(.horizontal, AppMetrics.Space.l)
        }
    }

    /// Ein Kategorie-Chip: getönter Kreis mit Kategorie-Icon, Titel darunter.
    private func categoryChip(_ chip: String) -> some View {
        let isActive = activeChip == chip
        return Button {
            runCategory(chip)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive
                              ? AnyShapeStyle(AppColor.accentPrimary)
                              : AnyShapeStyle(AppColor.surfaceTinted))
                        .frame(width: 54, height: 54)
                    Image(systemName: POICategory.symbol(forChip: chip))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isActive ? AppColor.onAccent : AppColor.accentPrimary)
                }
                Text(chip)
                    .font(AppTypography.footnote)
                    .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip) suchen")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Ausgangszustand: Gespeicherte, letzte und nahe Orte

    private var browseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                if !savedEntries.isEmpty {
                    section("Gespeicherte Orte", entries: savedEntries)
                }
                if !recentEntries.isEmpty {
                    section("Letzte Orte", entries: recentEntries)
                }
                if !nearbyEntries.isEmpty {
                    section("In der Nähe", entries: nearbyEntries)
                }
                if savedEntries.isEmpty && recentEntries.isEmpty && nearbyEntries.isEmpty {
                    emptyBrowseState
                }
            }
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.bottom, AppMetrics.Space.xl)
        }
    }

    // MARK: - Ergebnisliste (Suche / Kategorie)

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                section(resultsHeader, entries: resultEntries)
            }
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.bottom, AppMetrics.Space.xl)
        }
    }

    /// Kopfzeile der Ergebnisliste. Bei einer Kategorie sind es bewusst nur
    /// die nächstgelegenen Orte – das steht auch so da, damit niemand die
    /// Liste für vollständig hält.
    private var resultsHeader: String {
        if activeChip != nil {
            return results.count == 1
                ? "Nächster Ort in der Umgebung"
                : "Die \(results.count) nächsten in der Umgebung"
        }
        return "\(results.count) Ergebnisse · nach Entfernung"
    }

    // MARK: - Abschnitt und Zeile

    private func section(_ title: String, entries: [PlaceEntry]) -> some View {
        SheetSection(title: title) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                placeRow(entry, showsDivider: index < entries.count - 1)
            }
        }
    }

    /// Listenzeile: Icon, Name, Untertitel, Zugänglichkeit für das eigene
    /// Profil und die Distanz zum Standort.
    private func placeRow(_ entry: PlaceEntry, showsDivider: Bool) -> some View {
        let poi = entry.poi
        return VStack(spacing: 0) {
            Button {
                select(poi)
            } label: {
                HStack(spacing: AppMetrics.Space.m) {
                    SheetRowIcon(symbol: entry.symbol)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(poi.name)
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        if let subtitle = entry.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }

                        // Status vierfach codiert (Symbol + Form + Farbe +
                        // Text), damit er auch ohne Farbwahrnehmung trägt.
                        HStack(spacing: 6) {
                            Image(systemName: poi.accessStatus.symbolName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(poi.accessStatus.tint)
                            Text(poi.accessStatus.label)
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: AppMetrics.Space.s)

                    Text(viewModel.userDistanceText(to: poi))
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.horizontal, AppMetrics.Space.m)
                .padding(.vertical, 12)
                .frame(minHeight: AppMetrics.Touch.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(poi.name), \(poi.accessStatus.label), \(viewModel.userDistanceText(to: poi))")
            .accessibilityAddTraits(.isButton)

            if showsDivider {
                Rectangle()
                    .fill(AppColor.borderDecorative)
                    .frame(height: 1)
                    .padding(.leading, 36 + AppMetrics.Space.m + AppMetrics.Space.m)
            }
        }
    }

    // MARK: - Leerzustände

    private var emptyBrowseState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Noch keine Orte in der Nähe geladen.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppMetrics.Space.l)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Keine zugänglichen Orte für \u{201E}\(query)\u{201C} in der Nähe gefunden.")
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppMetrics.Space.xl)
            Text("Versuche einen anderen Suchbegriff oder vergrössere den Kartenausschnitt.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppMetrics.Space.xl)
        }
        .padding(.top, AppMetrics.Space.xxl)
    }

    // MARK: - Einträge

    private var savedEntries: [PlaceEntry] {
        savedPlaces.map { place in
            let resolved = poi(for: place)
            return PlaceEntry(
                id: "saved-\(place.id.uuidString)",
                poi: resolved,
                symbol: "bookmark.fill",
                subtitle: resolved.address
            )
        }
    }

    private var recentEntries: [PlaceEntry] {
        recentPlaces.map { place in
            PlaceEntry(
                id: "recent-\(place.id.uuidString)",
                poi: place.poi,
                symbol: "clock.arrow.circlepath",
                subtitle: recentSubtitle(place)
            )
        }
    }

    private var nearbyEntries: [PlaceEntry] {
        viewModel.nearbyPOIs().map { poi in
            PlaceEntry(
                id: "nearby-\(poi.id.uuidString)",
                poi: poi,
                symbol: poi.categorySymbol,
                subtitle: poi.address
            )
        }
    }

    private var resultEntries: [PlaceEntry] {
        results.map { poi in
            PlaceEntry(
                id: "result-\(poi.id.uuidString)",
                poi: poi,
                symbol: poi.categorySymbol,
                subtitle: poi.address
            )
        }
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
        let relative = place.destination.visitedAt
            .formatted(.relative(presentation: .named).locale(.appGerman))
        return "\(relative) zuletzt besucht"
    }

    // MARK: - Aktionen

    private func select(_ poi: POI) {
        onSelect(poi)
        dismiss()
    }

    /// Löst einen gespeicherten Ort auf einen echten Altstadt-POI auf (damit
    /// die Auswahl im gewohnten POI-Detail landet); fällt sonst auf einen
    /// leichten POI aus den gespeicherten Koordinaten zurück.
    private func poi(for place: SavedPlace) -> POI {
        viewModel.poi(named: place.displayName) ?? POI(savedPlace: place)
    }

    /// Gespeicherte Orte des Users laden (still: Fehler werden ignoriert, die
    /// Sektion bleibt dann einfach leer).
    private func loadSavedPlaces() async {
        savedPlaces = (try? await SavedPlacesService.shared.fetchSavedPlaces()) ?? []
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
        // Nur die nächstgelegenen Treffer – dieselbe Auswahl, die auch als
        // Marker auf der Karte und als Karten im AR-Bild erscheint.
        results = viewModel.poisForCategory(chip, limit: AppConfig.nearestCategoryLimit)
        hasSearched = true
    }
}