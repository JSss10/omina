// MapSettingsSheet.swift
// ARMikronav
//
// Karteneinstellungen als Overlay in Apple-Maps-Manier: über einen eigenen
// Button auf der Karte geöffnet, jederzeit oben rechts (X) wieder schliessbar.
// Bündelt die reinen Darstellungs-Optionen:
// – Kartenmodus (Karte/Satellit) als Auswahl-Kacheln
// – Darstellung (Automatisch/Hell/Dunkel)
// Sichtbarkeit von Orten/Barrieren und der Barrierentypen-Filter sind jetzt
// im Filter-Sheet neben der Suchleiste (SearchSheet).
// Alle Einstellungen wirken sofort (live) – das Schliessen ist reines Verlassen.

import SwiftUI

struct MapSettingsSheet: View {
    @ObservedObject var mapPreferences: MapPreferences
    @Environment(\.dismiss) private var dismiss

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
}