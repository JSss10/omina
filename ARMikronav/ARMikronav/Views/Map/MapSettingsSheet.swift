// MapSettingsSheet.swift
// ARMikronav
//
// Karteneinstellungen als Overlay in Apple-Maps-Manier: über einen eigenen
// Button auf der Karte geöffnet, jederzeit oben rechts (X) wieder schliessbar.
// Bündelt, was vorher über einzelne Karten-Buttons verstreut war:
// – Kartenmodus (Karte/Satellit) als Auswahl-Kacheln
// – Darstellung (Automatisch/Hell/Dunkel)
// – Ein-/Ausblenden von Orten (POIs) und Barrieren
// – Einstieg in den Barrierentypen-Filter (FilterSheet)
// Alle Einstellungen wirken sofort (live) – das Schliessen ist reines Verlassen.

import SwiftUI

struct MapSettingsSheet: View {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject var mapPreferences: MapPreferences
    @Environment(\.dismiss) private var dismiss

    /// Barrierentypen-Filter (als eigenes Sheet über den Einstellungen).
    @State private var showingFilter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Kartenmodus") {
                    mapModeTiles
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section("Darstellung") {
                    Picker("Darstellung", selection: $mapPreferences.appearance) {
                        ForEach(MapAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    Toggle(isOn: $viewModel.poisVisible) {
                        Label("Orte", systemImage: "mappin.circle.fill")
                            .foregroundStyle(.primary)
                    }
                    Toggle(isOn: $viewModel.barriersVisible) {
                        Label("Barrieren", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.primary)
                    }

                    // Einstieg in den Barrierentypen-Filter – ersetzt den
                    // früheren eigenen Filter-Button auf der Karte.
                    Button {
                        showingFilter = true
                    } label: {
                        HStack {
                            Label("Barrierentypen filtern", systemImage: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(filterSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(!viewModel.barriersVisible)
                } header: {
                    Text("Auf der Karte anzeigen")
                } footer: {
                    Text("Ausgeblendete Barrieren warnen weiterhin bei Annäherung – nur die Marker auf der Karte verschwinden.")
                }
            }
            .navigationTitle("Karteneinstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schliessen")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingFilter) {
            FilterSheet(initial: viewModel.filterState) { newFilter in
                viewModel.applyFilter(newFilter)
            }
            .trackScreen("filter")
        }
    }

    // MARK: - Kartenmodus-Kacheln

    private var mapModeTiles: some View {
        HStack(spacing: 12) {
            ForEach(MapStyleChoice.allCases) { choice in
                modeTile(choice)
            }
        }
    }

    private func modeTile(_ choice: MapStyleChoice) -> some View {
        let isSelected = mapPreferences.style == choice
        return Button {
            mapPreferences.style = choice
        } label: {
            VStack(spacing: 8) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                Text(choice.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card)
                    .stroke(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Kurzfassung, wie viele Barrierentypen aktuell eingeblendet sind.
    private var filterSummary: String {
        let active = viewModel.filterState.enabledTypes.count
        let total = BarrierType.allCases.count
        return active == total ? "Alle" : "\(active)/\(total)"
    }
}