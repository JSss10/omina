// FilterSheet.swift
// ARMikronav
//
// Filter-Sheet, das direkt neben der Suchleiste (SearchSheet) geöffnet wird.
// Bündelt, was vorher in den Karteneinstellungen verstreut war:
// – Ein-/Ausblenden von Orten (POIs) und Barrieren
// – Auswahl der auf der Karte sichtbaren Barrierentypen
// Alle Einstellungen wirken sofort (live) auf das MapViewModel.

import SwiftUI

struct FilterSheet: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $viewModel.poisVisible) {
                        Label("Orte", systemImage: "mappin.circle.fill")
                            .foregroundStyle(.primary)
                    }
                    Toggle(isOn: $viewModel.barriersVisible) {
                        Label("Barrieren", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Auf der Karte anzeigen")
                } footer: {
                    Text("Ausgeblendete Barrieren warnen weiterhin bei Annäherung – nur die Marker auf der Karte verschwinden.")
                }

                Section {
                    ForEach(BarrierType.allCases, id: \.self) { type in
                        Toggle(isOn: binding(for: type)) {
                            Label(type.localizedLabel, systemImage: type.symbolName)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel(type.localizedLabel)
                    }
                } header: {
                    Text("Barrierentypen")
                } footer: {
                    Text("Barrieren und Orte (POIs) decken die ganze Zürcher Altstadt ab; hier wählst du, welche Barrierentypen auf der Karte erscheinen.")
                }
                .disabled(!viewModel.barriersVisible)
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Fertig")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Ein einzelner Barrierentyp: liest/schreibt live auf den Filterzustand
    /// des MapViewModels (kein separater Draft mehr – der Filter wirkt sofort).
    private func binding(for type: BarrierType) -> Binding<Bool> {
        Binding(
            get: { viewModel.filterState.enabledTypes.contains(type) },
            set: { isOn in
                var newFilter = viewModel.filterState
                if isOn {
                    newFilter.enabledTypes.insert(type)
                } else {
                    newFilter.enabledTypes.remove(type)
                }
                viewModel.applyFilter(newFilter)
            }
        )
    }
}