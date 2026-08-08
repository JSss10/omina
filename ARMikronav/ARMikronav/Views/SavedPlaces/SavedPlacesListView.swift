// SavedPlacesListView.swift
// ARMikronav
//
// Liste der gespeicherten Orte (saved_places). Wird an zwei Stellen genutzt:
// – Einstellungen ("Gespeicherte Orte" im Profil): nur ansehen + löschen.
// – Karte (Bookmark-Button): mit onSelect, um einen Ort auf der Karte
//   anzusteuern.
// Löschen per Swipe ist in beiden Kontexten möglich.

import SwiftUI
import CoreLocation

struct SavedPlacesListView: View {
    /// Tap auf einen Ort (Karte: zentrieren). Ohne Callback sind die Zeilen
    /// nicht antippbar (Einstellungen).
    var onSelect: ((SavedPlace) -> Void)? = nil

    @State private var places: [SavedPlace] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                AppStateScreen.syncing(
                    title: "Orte werden geladen",
                    message: "Deine gespeicherten Orte werden mit deinem Konto abgeglichen."
                )
            } else if let loadError {
                errorState(loadError)
            } else if places.isEmpty {
                emptyState
            } else {
                placesList
            }
        }
        .navigationTitle("Gespeicherte Orte")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Noch keine gespeicherten Orte")
                .font(.headline)
            Text("Speichere Orte über \u{201E}Ort speichern\u{201C} im Orts-Detail auf der Karte.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Orte konnten nicht geladen werden")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Erneut versuchen") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Liste

    private var placesList: some View {
        List {
            ForEach(places) { place in
                if let onSelect {
                    Button {
                        onSelect(place)
                    } label: {
                        row(place)
                    }
                    .buttonStyle(.plain)
                } else {
                    row(place)
                }
            }
            .onDelete { offsets in
                delete(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ place: SavedPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle = subtitle(for: place) {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: place))
    }

    /// Distanz zum aktuellen Standort und Speicherdatum, soweit verfügbar.
    private func subtitle(for place: SavedPlace) -> String? {
        var parts: [String] = []
        if let distance = distanceText(for: place) {
            parts.append(distance)
        }
        if let createdAt = place.createdAt {
            parts.append("gespeichert am " + createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.appGerman)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func distanceText(for place: SavedPlace) -> String? {
        guard let userLocation = LocationService.shared.currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let meters = userLocation.distance(from: placeLocation)
        return DistanceFormatter.awayString(fromMeters: meters)
    }

    private func accessibilityText(for place: SavedPlace) -> String {
        var text = place.displayName
        if let distance = distanceText(for: place) {
            text += ", \(distance)"
        }
        return text
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            places = try await SavedPlacesService.shared.fetchSavedPlaces()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Optimistisch aus der Liste entfernen; bei Fehler Liste neu laden.
    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { places[$0] }
        places.remove(atOffsets: offsets)
        Task {
            for place in toDelete {
                do {
                    try await SavedPlacesService.shared.delete(id: place.id)
                } catch {
                    await load()
                    return
                }
            }
        }
    }
}