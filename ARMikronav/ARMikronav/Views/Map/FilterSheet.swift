// FilterSheet.swift
// ARMikronav
//
// Bottom-Sheet zum Setzen des Kartenfilters: Toggle pro Barrierentyp + Radius-Slider.
// Der Sheet arbeitet auf einer lokalen Draft-Kopie und übergibt das Endergebnis
// beim Schliessen an den Caller (MapView/MapViewModel).

import SwiftUI

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BarrierFilterState
    let onApply: (BarrierFilterState) -> Void

    init(initial: BarrierFilterState, onApply: @escaping (BarrierFilterState) -> Void) {
        self._draft = State(initialValue: initial)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Abbrechen/Fertig als Icons (X bzw. Häkchen) statt Text –
                // konsistent mit der schlankeren Karten-Bedienung.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(draft)
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
    }

    private func binding(for type: BarrierType) -> Binding<Bool> {
        Binding(
            get: { draft.enabledTypes.contains(type) },
            set: { isOn in
                if isOn {
                    draft.enabledTypes.insert(type)
                } else {
                    draft.enabledTypes.remove(type)
                }
            }
        )
    }
}