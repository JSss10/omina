// SavedPlacesListView.swift
// Omina
//
// Liste der gespeicherten Orte (saved_places), Aufbau nach Entwurf:
// Akzentleiste, Titel mit Einleitung und darunter je Ort eine getönte Karte:
// das Foto gross über die ganze Breite, darunter Name, Speicherdatum,
// Zugänglichkeit fürs eigene Profil, Distanz und Pfeil.
//
// Wird an zwei Stellen genutzt:
// – Profil-Tab ("Gespeicherte Orte"): nur ansehen + löschen.
// – Karte (Bookmark-Button): mit onSelect, um einen Ort anzusteuern.
// Löschen läuft über das Kontextmenü der Karte (Swipe gibt es ohne List nicht).

import SwiftUI
import CoreLocation

struct SavedPlacesListView: View {
    /// Tap auf einen Ort (Karte: zentrieren). Ohne Callback sind die Karten
    /// nicht antippbar (Profil-Tab).
    var onSelect: ((SavedPlace) -> Void)? = nil
    /// Profil des Users – bestimmt den Prozentwert «zugänglich für dich».
    /// Ohne Profil steht dort der allgemeine Status.
    var profile: UserProfile? = nil
    /// Aus dem Profil-Tab heraus aufgerufen bleibt die Navigationsleiste
    /// sichtbar, damit der Weg zurück offen ist; als eigener Tab steht der
    /// Screen wie im Entwurf ohne Leiste.
    var showsNavigationBar: Bool = false

    @State private var places: [SavedPlace] = []
    @State private var poisById: [UUID: POI] = [:]
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            Group {
                if isLoading {
                    AppStateScreen.syncing(
                        title: "Orte werden geladen",
                        message: "Deine gespeicherten Orte werden mit deinem Konto abgeglichen."
                    )
                } else if let loadError {
                    errorState(loadError)
                } else {
                    content
                }
            }
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(showsNavigationBar ? "Gespeicherte Orte" : "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                AuthHeader(
                    title: "Gespeicherte Orte",
                    subtitle: places.isEmpty
                        ? "Hier sammelst du Orte, die für dich funktionieren."
                        : "Deine Orte – mit Zugänglichkeit und Entfernung auf einen Blick."
                )

                if places.isEmpty {
                    emptyState
                } else {
                    ForEach(places) { place in
                        placeCard(place)
                    }
                }
            }
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.bottom, AppMetrics.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await load() }
    }

    // MARK: - Karte eines Ortes

    @ViewBuilder
    private func placeCard(_ place: SavedPlace) -> some View {
        let card = cardContent(place)

        Group {
            if let onSelect {
                Button {
                    onSelect(place)
                } label: {
                    card
                }
                .buttonStyle(.plain)
            } else {
                card
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                delete(place)
            } label: {
                Label("Entfernen", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: place))
        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
    }

    /// Foto gross über die ganze Kartenbreite, darunter der Text – so bleibt
    /// er auch bei langen Namen und Zeitangaben vollständig lesbar (vorher
    /// stand das Bild links daneben und quetschte die Zeilen).
    private func cardContent(_ place: SavedPlace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail(for: place)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()

            HStack(alignment: .center, spacing: AppMetrics.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.displayName)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textBrand)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let saved = savedText(for: place) {
                        Text(saved)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessLine(for: place)
                }

                Spacer(minLength: AppMetrics.Space.s)

                if let distance = distanceText(for: place) {
                    Text(distance)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textBrand)
                        .monospacedDigit()
                        .fixedSize()
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColor.textBrand)
            }
            .padding(AppMetrics.Space.m)
        }
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
    }

    /// Foto des Ortes aus dem Tourismus-API; ohne Bild die getönte Fläche.
    @ViewBuilder
    private func thumbnail(for place: SavedPlace) -> some View {
        if let url = poi(for: place)?.images.first?.url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            AppColor.accentMuted
            Image(systemName: "bookmark.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
        }
    }

    /// Zugänglichkeit fürs eigene Profil – Symbol und Text, nie nur Farbe.
    @ViewBuilder
    private func accessLine(for place: SavedPlace) -> some View {
        if let poi = poi(for: place) {
            let rating = profile.flatMap { poi.gintoRating(for: $0.wheelchairType) }
            let status = rating?.status ?? poi.accessStatus
            let text: String = {
                if let percent = rating?.conformancePercent {
                    return "Zu \(Int(percent))% zugänglich für dich"
                }
                return status.label
            }()

            HStack(spacing: AppMetrics.Space.s - 2) {
                Image(systemName: status.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status.tint)
                Text(text)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func poi(for place: SavedPlace) -> POI? {
        place.referenceId.flatMap { poisById[$0] }
    }

    // MARK: - Zustände

    private var emptyState: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Noch keine gespeicherten Orte")
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textBrand)
            Text("Tippe im Orts-Detail auf «Speichern» – dann findest du den Ort hier wieder.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppMetrics.Space.xl)
    }

    private func errorState(_ message: String) -> some View {
        AppStateScreen(
            symbol: "exclamationmark.triangle",
            title: "Orte konnten nicht geladen werden",
            message: message,
            primaryAction: AppStateScreen.Action("Erneut versuchen") {
                Task { await load() }
            }
        )
    }

    // MARK: - Texte

    /// Wann der Ort gespeichert wurde, relativ formuliert («gestern gespeichert»).
    private func savedText(for place: SavedPlace) -> String? {
        guard let createdAt = place.createdAt else { return nil }
        let relative = createdAt.formatted(.relative(presentation: .named).locale(.appGerman))
        return "\(relative) gespeichert"
    }

    private func distanceText(for place: SavedPlace) -> String? {
        guard let userLocation = LocationService.shared.currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return DistanceFormatter.string(fromMeters: userLocation.distance(from: placeLocation))
    }

    private func accessibilityText(for place: SavedPlace) -> String {
        var parts = [place.displayName]
        if let saved = savedText(for: place) { parts.append(saved) }
        if let poi = poi(for: place) {
            let rating = profile.flatMap { poi.gintoRating(for: $0.wheelchairType) }
            if let percent = rating?.conformancePercent {
                parts.append("zu \(Int(percent)) Prozent zugänglich für dich")
            } else {
                parts.append(poi.accessStatus.label)
            }
        }
        if let distance = distanceText(for: place) { parts.append(distance) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Laden und Löschen

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            places = try await SavedPlacesService.shared.fetchSavedPlaces()
        } catch {
            loadError = ErrorText.message(for: error)
        }
        isLoading = false
        await loadPlaceDetails()
    }

    /// Fotos und Zugänglichkeit stehen am POI, nicht am gespeicherten Eintrag –
    /// deshalb einmal die Orte der Altstadt laden und über die Referenz zuordnen.
    private func loadPlaceDetails() async {
        guard !places.isEmpty, poisById.isEmpty else { return }
        guard let pois = try? await POIRepository.shared.fetchPOIs(
            near: AppConfig.altstadtCenter,
            radius: AppConfig.altstadtRadiusM
        ) else { return }
        poisById = Dictionary(pois.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Optimistisch aus der Liste entfernen; bei Fehler Liste neu laden.
    private func delete(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
        Task {
            do {
                try await SavedPlacesService.shared.delete(id: place.id)
            } catch {
                await load()
            }
        }
    }
}