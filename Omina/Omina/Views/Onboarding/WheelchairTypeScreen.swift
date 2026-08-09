// Screen12_WheelchairType.swift
// Omina – Onboarding Schritt 2/6: Rollstuhltyp wählen.
// 15 Subtypen in 5 Kategorien gruppiert, Mapping auf internen WheelchairType.

import SwiftUI

struct Screen12_WheelchairType: View {
    @Binding var draft: DraftProfile
    let onSelect: (WheelchairSubtype) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
            ForEach(WheelchairCategory.allCases) { category in
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    Text(category.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, AppMetrics.Space.xs)

                    ForEach(category.subtypes) { subtype in
                        SelectionRow(
                            label: subtype.displayName,
                            selected: draft.wheelchairSubtype == subtype
                        ) {
                            onSelect(subtype)
                        }
                    }
                }
            }

            Text("Dein gewählter Typ bestimmt die Standard-Schwellenwerte für Breite, Steigung und Bordsteine. Du kannst diese in den nächsten Schritten anpassen.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, AppMetrics.Space.xs)
        }
    }
}