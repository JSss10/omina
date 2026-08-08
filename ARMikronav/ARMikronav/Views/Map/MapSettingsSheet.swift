// MapSettingsSheet.swift
// ARMikronav
//
// Karteneinstellungen als Sheet: über den Ebenen-Button links oben auf der
// Karte geöffnet, jederzeit über X oder Häkchen wieder schliessbar.
// Bündelt die reinen Darstellungs-Optionen:
// – Kartenmodus (Karte/Satellit) als Auswahl-Kacheln
// – Darstellung (Automatisch/Hell/Dunkel) als Segment-Umschalter
// Sichtbarkeit von Orten/Barrieren und der Barrieretypen-Filter sind im
// Filter-Sheet neben der Suchleiste.
// Alle Einstellungen wirken sofort (live) – das Schliessen ist reines Verlassen.

import SwiftUI

struct MapSettingsSheet: View {
    @ObservedObject var mapPreferences: MapPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Karteneinstellungen",
                onClose: { dismiss() },
                onConfirm: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    mapModeSection
                    appearanceSection
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.s)
                .padding(.bottom, AppMetrics.Space.xl)
            }
        }
        .background(AppColor.backgroundPrimary)
        .presentationBackground(AppColor.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Kartenmodus

    private var mapModeSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Kartenmodus")
                .font(AppTypography.headline)
                .foregroundColor(AppColor.accentPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: AppMetrics.Space.m) {
                ForEach(MapStyleChoice.allCases) { choice in
                    modeTile(choice)
                }
            }
        }
    }

    private func modeTile(_ choice: MapStyleChoice) -> some View {
        let isSelected = mapPreferences.style == choice
        return Button {
            mapPreferences.style = choice
        } label: {
            VStack(spacing: AppMetrics.Space.s) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(AppColor.accentPrimary)
                Text(choice.label)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppMetrics.Space.l)
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )
            // Die Auswahl trägt nicht die Farbe allein: Der gewählte Modus
            // bekommt zusätzlich einen Rahmen (Styleguide §2.3, P2).
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.accentPrimary : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Darstellung

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Darstellung")
                .font(AppTypography.headline)
                .foregroundColor(AppColor.accentPrimary)
                .accessibilityAddTraits(.isHeader)

            SegmentedBar(
                segments: MapAppearance.allCases.map {
                    SegmentedBar<MapAppearance>.Segment(value: $0, label: $0.label)
                },
                selection: $mapPreferences.appearance
            )
        }
    }
}