// FilterSheet.swift
// Omina
//
// Filter-Sheet, das direkt neben der Suchleiste (SearchSheet) geöffnet wird.
// Bündelt, was vorher in den Karteneinstellungen verstreut war:
// – Ein-/Ausblenden von Orten (POIs) und Barrieren
// – Auswahl der auf der Karte sichtbaren Barrieretypen
// Alle Einstellungen wirken sofort (live) auf das MapViewModel; das Häkchen
// oben rechts schliesst nur, es gibt nichts zu bestätigen.

import SwiftUI

struct FilterSheet: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Filter", onClose: { dismiss() }, onConfirm: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    visibilitySection
                    barrierTypeSection
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

    // MARK: - Auf der Karte anzeigen

    private var visibilitySection: some View {
        SheetSection(
            title: "Auf der Karte anzeigen",
            footnote: "Ausgeblendete Barrieren warnen weiterhin bei Annäherung – nur die Marker auf der Karte verschwinden."
        ) {
            SheetToggleRow(
                symbol: "mappin",
                title: "Orte",
                isOn: $viewModel.poisVisible
            )
            SheetToggleRow(
                symbol: "exclamationmark.triangle.fill",
                title: "Barrieren",
                isOn: $viewModel.barriersVisible,
                showsDivider: false
            )
        }
    }

    // MARK: - Barrieretypen

    private var barrierTypeSection: some View {
        SheetSection(
            title: "Barrieretypen",
            footnote: "Barrieren und Orte decken die ganze Zürcher Altstadt ab; hier wählst du, welche Barrieretypen als Marker erscheinen."
        ) {
            ForEach(BarrierType.allCases, id: \.self) { type in
                SheetToggleRow(
                    symbol: type.symbolName,
                    title: type.localizedLabel,
                    isOn: binding(for: type),
                    showsDivider: type != BarrierType.allCases.last
                )
            }
        }
        // Ohne sichtbare Barrieren hat die Typenauswahl keine Wirkung.
        .disabled(!viewModel.barriersVisible)
        .opacity(viewModel.barriersVisible ? 1 : 0.5)
    }

    /// Ein einzelner Barrieretyp: liest/schreibt live auf den Filterzustand
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