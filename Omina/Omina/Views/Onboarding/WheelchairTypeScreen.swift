// Screen12_WheelchairType.swift
// Omina – Onboarding Schritt 3/8: Rollstuhltyp wählen.
// 15 Subtypen in 5 Kategorien gruppiert, Mapping auf internen WheelchairType.
// Aufbau nach Entwurf: violette Gruppenüberschrift, darunter die getönten
// Auswahlzeilen mit Leit-Symbol und Auswahlpunkt.

import SwiftUI

struct Screen12_WheelchairType: View {
    @Binding var draft: DraftProfile
    let onSelect: (WheelchairSubtype) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.xl) {
            ForEach(WheelchairCategory.allCases) { category in
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    Text(category.displayName)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.accentPrimary)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(category.subtypes) { subtype in
                        SelectionRow(
                            label: subtype.displayName,
                            icon: subtype.icon,
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}