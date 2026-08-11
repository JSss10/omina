// HomeDashboardView.swift
// Omina
//
// Homescreen (Start-Tab), Aufbau nach Entwurf: oben Profilbild, Begrüssung
// und das Wetter als Kapsel, darunter Suche mit Filter und die Kategorien als
// Chips. Dann die letzten Ziele als Bildkarten und zuunterst die neuesten
// Barrieren-Meldungen als Zeilen.
//
// Karten-Interaktionen laufen über Callbacks nach oben: Die Suche öffnet nur
// die Karte, ein letztes Ziel bzw. eine Barriere öffnet sie direkt beim
// zugehörigen Detail-Sheet.

import SwiftUI
import CoreLocation

struct HomeDashboardView: View {
    /// Wechselt zum Karten-Tab (Tap auf die Suche).
    let onOpenMap: () -> Void
    /// Öffnet die Karte und dort gleich das Filter-Overlay (Tap auf Filter).
    let onOpenFilter: () -> Void
    /// Öffnet die Karte mit vorgewählter Kategorie (Chip-Reihe).
    let onSelectCategory: (String) -> Void
    /// Öffnet die Karte direkt beim POI-Detail des angetippten Ziels.
    let onOpenDestination: (RecentDestination) -> Void
    /// Öffnet die Karte direkt beim Detail der angetippten Barriere.
    let onOpenBarrier: (Barrier) -> Void
    /// Anzahl gesetzter Kartenfilter – als Plakette an der Filter-Schaltfläche.
    var activeFilterCount: Int = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var viewModel = HomeDashboardViewModel()
    @StateObject private var recentDestinations = RecentDestinationsStore.shared
    @StateObject private var avatarStore = AvatarStore.shared

    /// Zuletzt gewählte Kategorie – hebt den Chip hervor.
    @State private var selectedCategory: String?

    /// Sortierung der beiden Listen – im Entwurf jeweils rechts neben dem Titel.
    @State private var destinationSort: ListSort = .newest
    @State private var barrierSort: ListSort = .newest

    /// Wetterdetails (UV-Index, gefühlte Temperatur, Wind) als Sheet.
    @State private var showingWeather = false

    // Feldtest: Nur während eines aktiven Testlaufs erscheint oben rechts der
    // "Test beenden"-Button. Er lädt offene Tracking-Events hoch und setzt das
    // Gerät für die nächste Testperson zurück.
    @ObservedObject private var fieldTest = FieldTestService.shared
    @State private var showEndTestConfirmation = false
    @State private var isEndingTest = false

    /// Sortierreihenfolge der Listen auf dem Homescreen.
    enum ListSort: String, CaseIterable, Identifiable {
        case newest, nearest, name

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newest:  return "Neueste zuerst"
            case .nearest: return "Nächste zuerst"
            case .name:    return "Nach Name"
            }
        }
    }

    var body: some View {
        if fieldTest.isActive {
            NavigationStack {
                dashboard
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { endTestToolbarItem }
                    .confirmationDialog(
                        "Test beenden?",
                        isPresented: $showEndTestConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Test beenden", role: .destructive) { endTest() }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Deine Antworten werden hochgeladen und das Gerät wird danach für die nächste Testperson zurückgesetzt.")
                    }
                    .overlay { endTestProgressOverlay }
            }
        } else {
            dashboard
        }
    }

    // Der eigentliche Homescreen-Inhalt (ohne den Feldtest-Rahmen).
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                header
                searchRow
                categoryRow

                sectionDivider
                recentDestinationsSection

                sectionDivider
                newBarriersSection
            }
            .padding(.top, AppMetrics.Space.s)
            .padding(.bottom, AppMetrics.Space.xl)
        }
        .background(AppColor.backgroundPrimary)
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            viewModel.start()
            avatarStore.loadIfNeeded()
        }
        .sheet(isPresented: $showingWeather) {
            WeatherDetailSheet(
                weather: viewModel.weather,
                placeName: viewModel.weatherPlaceName,
                errorMessage: viewModel.weatherError
            )
        }
    }

    /// Feine Linie zwischen den Blöcken (Entwurf).
    private var sectionDivider: some View {
        Rectangle()
            .fill(AppColor.borderDecorative)
            .frame(height: 1)
            .padding(.horizontal, AppMetrics.Space.l)
            .accessibilityHidden(true)
    }

    // MARK: - Begrüssung und Wetter

    /// Begrüssung, Name und Wetter stehen nebeneinander. Ab den
    /// Accessibility-Textgrössen rutscht das Wetter unter die Begrüssung –
    /// beides nebeneinander würde dort nicht mehr vollständig hineinpassen.
    @ViewBuilder
    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
                    HStack(spacing: AppMetrics.Space.m) {
                        avatar
                        greetingLines
                        Spacer(minLength: 0)
                    }
                    weatherPill
                }
            } else {
                HStack(spacing: AppMetrics.Space.m) {
                    avatar
                    greetingLines
                    Spacer(minLength: AppMetrics.Space.s)
                    weatherPill
                }
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
    }

    /// Begrüssung und Name stehen je auf einer eigenen Zeile und werden nie
    /// umgebrochen oder abgeschnitten: Wird es eng (langer Name, grosse
    /// Textstufe), verkleinert sich die Schrift, bis beides ganz hineinpasst.
    private var greetingLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.salutation + ",")
                .foregroundStyle(AppColor.textBrand)
            Text(viewModel.firstName ?? "willkommen")
                .foregroundStyle(AppColor.accentPrimary)
        }
        .font(AppTypography.title3)
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.5)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.greeting)
    }

    /// Profilbild (in den Einstellungen erfasst), sonst Initialen-Monogramm.
    private var avatar: some View {
        ZStack {
            if let photo = avatarStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(AppColor.surfaceTinted)
                if viewModel.initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.accentPrimary)
                } else {
                    Text(viewModel.initials)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Wetter als Kapsel: die Temperatur gross und ungekürzt links, das
    /// Wettersymbol rechts im violetten Kreis. Ein Tipp öffnet die Details
    /// (gefühlte Temperatur, UV-Index, Feuchte, Wind). Ohne Daten bleibt die
    /// Kapsel mit Strich stehen und führt zur Erklärung im Sheet.
    private var weatherPill: some View {
        Button {
            showingWeather = true
        } label: {
            HStack(spacing: AppMetrics.Space.s) {
                Text(temperatureText)
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textBrand)
                    .monospacedDigit()
                    .lineLimit(1)
                    // Die Temperatur ist die Kernaussage der Kapsel: Sie darf
                    // nie umbrechen oder gekürzt werden, auch wenn die
                    // Begrüssung daneben lang ist.
                    .fixedSize()

                Image(systemName: viewModel.weather?.symbolName ?? "cloud.slash")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 56, height: 56)
                    .background(AppColor.accentPrimary, in: Circle())
            }
            .padding(.leading, AppMetrics.Space.m)
            .background(AppColor.surfaceTinted, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Die Kapsel behält immer ihre volle Breite: Temperatur und Symbol
        // werden nie gequetscht oder abgeschnitten, auch neben einer langen
        // Begrüssung nicht.
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weatherAccessibilityText)
        .accessibilityHint("Öffnet die Wetterdetails")
        .accessibilityAddTraits(.isButton)
    }

    /// Temperatur der Kapsel, ohne Daten ein Strich.
    private var temperatureText: String {
        guard let weather = viewModel.weather else { return "–" }
        return "\(Int(weather.temperatureC.rounded())) °C"
    }

    private var weatherAccessibilityText: String {
        guard let weather = viewModel.weather else {
            return "Wetter derzeit nicht verfügbar"
        }
        var text = "Aktuelles Wetter"
        if let place = viewModel.weatherPlaceName {
            text += " in \(place)"
        }
        text += ": \(Int(weather.temperatureC.rounded())) Grad, \(weather.conditionDescription),"
        text += " gefühlt \(Int(weather.feelsLikeC.rounded())) Grad,"
        text += " UV-Index \(Int(weather.uvIndex.rounded())) (\(weather.uvCategory))"
        return text
    }

    // MARK: - Suche und Kategorien

    private var searchRow: some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Button {
                onOpenMap()
            } label: {
                SearchBar(placeholder: "Suchst du nach etwas Bestimmten?")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Orte suchen")
            .accessibilityHint("Öffnet die Suche auf der Karte")

            // Filter führt auf die Karte und öffnet dort direkt das
            // Filter-Overlay – der Filter wirkt auf die Karte, also wird er
            // auch dort gesetzt.
            FilterIconButton(activeCount: activeFilterCount) {
                onOpenFilter()
            }
            .accessibilityHint("Öffnet die Karte mit den Filtern")
        }
        .padding(.horizontal, AppMetrics.Space.l)
    }

    /// Kategorien als Chips – ein Tap führt mit der Kategorie auf die Karte.
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                ForEach(POICategory.chipLabels, id: \.self) { chip in
                    CategoryPill(
                        label: chip,
                        symbol: POICategory.symbol(forChip: chip),
                        isSelected: selectedCategory == chip
                    ) {
                        selectedCategory = chip
                        onSelectCategory(chip)
                    }
                }
            }
            .padding(.horizontal, AppMetrics.Space.l)
        }
        .scrollClipDisabled()
    }

    // MARK: - Letzte Ziele

    private var recentDestinationsSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
            sectionHeader("Letzte Ziele", sort: $destinationSort)

            if sortedDestinations.isEmpty {
                emptyRow(
                    symbol: "mappin.slash",
                    text: "Noch keine Ziele – starte eine Navigation auf der Karte."
                )
                .padding(.horizontal, AppMetrics.Space.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppMetrics.Space.m) {
                        ForEach(sortedDestinations) { destination in
                            destinationCard(destination)
                        }
                    }
                    .padding(.horizontal, AppMetrics.Space.l)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// Bildkarte eines Ziels; ohne Foto bleibt die getönte Fläche stehen.
    /// Ein Tipp führt auf die Karte und öffnet dort gleich das POI-Detail.
    private func destinationCard(_ destination: RecentDestination) -> some View {
        Button {
            onOpenDestination(destination)
        } label: {
            ZStack(alignment: .bottom) {
                Group {
                    if let url = destination.imageURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            destinationPlaceholder
                        }
                    } else {
                        destinationPlaceholder
                    }
                }
                .frame(width: 160, height: 190)
                .clipped()

                Text(destination.name)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textBrand)
                    .lineLimit(1)
                    .padding(.horizontal, AppMetrics.Space.m)
                    .padding(.vertical, AppMetrics.Space.s)
                    .background(AppColor.backgroundPrimary, in: Capsule())
                    .padding(.horizontal, AppMetrics.Space.s)
                    .padding(.bottom, AppMetrics.Space.m)
            }
            .frame(width: 160, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(destination.name), \(destinationSubtitle(destination)), öffnet den Ort auf der Karte")
        .accessibilityAddTraits(.isButton)
    }

    private var destinationPlaceholder: some View {
        ZStack {
            AppColor.surfaceTinted
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(AppColor.accentPrimary)
        }
    }

    private var sortedDestinations: [RecentDestination] {
        let all = recentDestinations.destinations
        switch destinationSort {
        case .newest:
            return all
        case .name:
            return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nearest:
            return all.sorted {
                (viewModel.distance(latitude: $0.latitude, longitude: $0.longitude) ?? .greatestFiniteMagnitude)
                    < (viewModel.distance(latitude: $1.latitude, longitude: $1.longitude) ?? .greatestFiniteMagnitude)
            }
        }
    }

    private func destinationSubtitle(_ destination: RecentDestination) -> String {
        var parts = [destination.visitedAt.formatted(.relative(presentation: .named).locale(.appGerman))]
        if let distance = viewModel.distanceText(
            latitude: destination.latitude,
            longitude: destination.longitude
        ) {
            parts.append(distance)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Neue Barrieren

    private var newBarriersSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
            sectionHeader("Neue Barrieren", sort: $barrierSort)

            Group {
                if viewModel.isLoadingBarriers && viewModel.newBarriers.isEmpty {
                    loadingRow
                } else if let error = viewModel.barriersError {
                    errorRow(error)
                } else if viewModel.newBarriers.isEmpty {
                    emptyRow(
                        symbol: "checkmark.seal.fill",
                        text: "Keine neuen Barrieren-Meldungen in der Altstadt."
                    )
                } else {
                    VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                        ForEach(sortedBarriers) { barrier in
                            barrierRow(barrier)
                        }
                    }
                }
            }
            .padding(.horizontal, AppMetrics.Space.l)
        }
    }

    private var sortedBarriers: [Barrier] {
        let all = viewModel.newBarriers
        switch barrierSort {
        case .newest:
            return all
        case .name:
            return all.sorted { $0.type.localizedLabel < $1.type.localizedLabel }
        case .nearest:
            return all.sorted {
                (viewModel.distance(latitude: $0.latitude, longitude: $0.longitude) ?? .greatestFiniteMagnitude)
                    < (viewModel.distance(latitude: $1.latitude, longitude: $1.longitude) ?? .greatestFiniteMagnitude)
            }
        }
    }

    /// Eine Barrieren-Meldung: Symbol im getönten Kreis, Typ, Detailzeile.
    /// Ein Tipp führt auf die Karte und öffnet dort gleich das Barrieren-Detail.
    private func barrierRow(_ barrier: Barrier) -> some View {
        Button {
            onOpenBarrier(barrier)
        } label: {
            HStack(spacing: AppMetrics.Space.m) {
                Image(systemName: barrier.type.symbolName)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 56, height: 56)
                    .background(AppColor.accentMuted, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(barrier.type.localizedLabel)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textBrand)
                    if let subtitle = barrierSubtitle(barrier) {
                        Text(subtitle)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(2)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(barrierAccessibilityText(barrier))
        .accessibilityAddTraits(.isButton)
    }

    /// Messwert, Distanz und Meldedatum der Barriere als eine Zeile.
    private func barrierSubtitle(_ barrier: Barrier) -> String? {
        var parts: [String] = []
        switch barrier.type {
        case .steps:
            if let v = barrier.value { parts.append("\(Int(v)) Stufen") }
        case .curb, .curbMissing:
            if let v = barrier.value { parts.append("\(Int(v)) cm hoch") }
        case .incline:
            if let v = barrier.value { parts.append("\(Int(v)) % Steigung") }
        case .narrow:
            if let v = barrier.value { parts.append("\(Int(v)) cm Durchgang") }
        case .surface:
            if let s = barrier.subtype {
                parts.append(BarrierType.localizedSurface(s))
            }
        case .temporary:
            break
        }
        if let distance = viewModel.distanceText(
            latitude: barrier.latitude,
            longitude: barrier.longitude
        ) {
            parts.append("in \(distance)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func barrierAccessibilityText(_ barrier: Barrier) -> String {
        var parts = [barrier.type.localizedLabel]
        if let subtitle = barrierSubtitle(barrier) { parts.append(subtitle) }
        parts.append("öffnet die Barriere auf der Karte")
        return parts.joined(separator: ", ")
    }

    // MARK: - Bausteine

    /// Abschnittskopf mit Titel links und der Sortierung rechts.
    private func sectionHeader(_ title: String, sort: Binding<ListSort>) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Menu {
                Picker("Sortieren", selection: sort) {
                    ForEach(ListSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: AppMetrics.Space.s) {
                    Text("Sortieren")
                        .font(AppTypography.body)
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 17, weight: .regular))
                }
                .foregroundStyle(AppColor.textBrand)
                .frame(minHeight: AppMetrics.Touch.minimum)
            }
            .accessibilityLabel("Sortieren: \(sort.wrappedValue.label)")
        }
        .padding(.horizontal, AppMetrics.Space.l)
    }

    private var loadingRow: some View {
        HStack(spacing: AppMetrics.Space.m) {
            ProgressView()
                .tint(AppColor.accentPrimary)
            Text("Meldungen werden geladen …")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.Status.limitedIcon)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Erneut") {
                Task { await viewModel.loadBarriers() }
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColor.accentPrimary)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    private func emptyRow(symbol: String, text: String) -> some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(AppColor.accentPrimary)
            Text(text)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    // MARK: - Feldtest: Test beenden

    @ToolbarContentBuilder
    private var endTestToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showEndTestConfirmation = true
            } label: {
                Text("Test beenden")
                    .font(AppTypography.headline)
            }
            .disabled(isEndingTest)
            .accessibilityLabel("Test beenden")
        }
    }

    /// Blendet während des Beendens einen Fortschritts-Overlay ein, damit die
    /// Testperson sieht, dass Daten hochgeladen werden.
    @ViewBuilder
    private var endTestProgressOverlay: some View {
        if isEndingTest {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                VStack(spacing: AppMetrics.Space.m) {
                    ProgressView()
                        .tint(.white)
                    Text("Test wird beendet…")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(AppMetrics.Space.l)
                .background(
                    AppColor.Violet.v800,
                    in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                )
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    /// Lädt offene Events hoch und setzt das Gerät zurück. Danach wechselt die
    /// App über den Auth-State automatisch zurück zum Welcome-Screen für die
    /// nächste Testperson.
    private func endTest() {
        guard !isEndingTest else { return }
        isEndingTest = true
        Task {
            await FieldTestService.shared.endTest()
            isEndingTest = false
        }
    }
}