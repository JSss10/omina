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
    /// Gespeicherte Orte des Users – im Ausgangszustand ganz oben gelistet,
    /// damit man sie direkt aus der Suche ansteuern kann.
    @State private var savedPlaces: [SavedPlace] = []
    /// Aktiver Kategorie-Chip (für die Hervorhebung); nil bei Freitext-Suche.
    @State private var activeChip: String?
    /// Sheet-Höhe: startet als Medium, wächst beim Tippen auf die volle Höhe.
    @State private var detent: PresentationDetent = .medium
    /// Filter-Sheet (Sichtbarkeit von Orten/Barrieren + Barrierentypen) – jetzt
    /// direkt neben der Suchleiste statt in den Karteneinstellungen.
    @State private var showingFilter = false
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Suchfeld und – direkt rechts daneben – der Filter-Button für die
            // Barrierentypen und die Sichtbarkeit von Orten/Barrieren.
            HStack(spacing: 12) {
                searchField
                filterButton
            }
            .padding(.horizontal)
            // Mehr Luft zwischen Grabber und Suchfeld.
            .padding(.top, 20)

            categoryFilters

            content
        }
        // Durchgehend der gruppierte Hintergrund (wie die insetGrouped-Liste),
        // damit Suchfeld, Kategorien und Liste auf derselben Fläche liegen –
        // Medium- und Voll-Ansicht sehen dadurch identisch aus.
        .background(Color(.systemGroupedBackground))
        .presentationBackground(Color(.systemGroupedBackground))
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
    /// Orte/Barrieren ausgeblendet oder nicht alle Barrierentypen sichtbar.
    private var filterButton: some View {
        Button {
            showingFilter = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filtersActive ? Color.white : AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(
                    filtersActive
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Weisse Pille auf dem gruppierten (grauen) Sheet-Hintergrund – hebt
        // sich wie die Listen-Karten ab (statt grau auf grau).
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    /// Kategorie-Filter (Café, WC, Restaurant …) als kreisförmige Icon-Buttons
    /// mit Titel darunter (Apple-Maps-Manier).
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(POICategory.chipLabels, id: \.self) { chip in
                    categoryChip(chip)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Ein Kategorie-Chip: farbiger Kreis mit Kategorie-Icon und Titel darunter.
    private func categoryChip(_ chip: String) -> some View {
        let isActive = activeChip == chip
        return Button {
            runCategory(chip)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                        .frame(width: 54, height: 54)
                    Image(systemName: POICategory.symbol(forChip: chip))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isActive ? Color.white : AppColor.accentPrimary)
                }
                Text(chip)
                    .font(.caption)
                    .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip) suchen")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Ausgangszustand: Letzte Orte + In der Nähe

    /// Ohne aktive Suche: zuletzt angesteuerte Orte und die nächstgelegenen
    /// POIs als Liste mit Icon und Name.
    private var browseList: some View {
        List {
            if !savedPlaces.isEmpty {
                Section("Gespeicherte Orte") {
                    ForEach(savedPlaces) { place in
                        let resolved = poi(for: place)
                        Button {
                            select(resolved)
                        } label: {
                            placeRow(
                                poi: resolved,
                                leadingSymbol: "bookmark.fill",
                                subtitle: resolved.address
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

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

            if savedPlaces.isEmpty && recentPlaces.isEmpty && nearby.isEmpty {
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
        .padding(.vertical, 8)
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

    /// Ergebnisliste: gleiche Zeilen-Optik und Listenform wie der
    /// Ausgangszustand (browseList), damit Medium- und Voll-Ansicht des Sheets
    /// einheitlich aussehen.
    private var resultsList: some View {
        List {
            Section {
                ForEach(results) { poi in
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
            } header: {
                Text(resultsHeader)
            }
        }
        .listStyle(.insetGrouped)
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