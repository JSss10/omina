// SelectionRow.swift
// Omina
//
// Auswählbare Zeile (Single-Choice) gemäss Styleguide v1.0: angehobene
// Kartenfläche, im ausgewählten Zustand getönt mit Akzent-Rahmen und
// Häkchen. Optionales Leit-Icon. Wird in den Onboarding-Auswahlschritten
// verwendet (Mobilitätskategorie, Rollstuhltyp) und hält so die Auswahl
// überall gleich modern und barrierefrei (Touch-Ziel >= 44 pt, P2-codiert).

import SwiftUI

struct SelectionRow: View {
    let label: String
    /// Optionales SF-Symbol als Leit-Icon (nil = ohne Icon, kompaktere Zeile).
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppMetrics.Space.m) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textSecondary)
                        .frame(width: 28)
                }

                Text(label)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: AppMetrics.Space.s)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.borderFunctional)
            }
            .padding(.horizontal, AppMetrics.Space.m)
            .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
            .frame(minHeight: AppMetrics.Touch.primary)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                    .fill(selected ? AppColor.Violet.v100 : AppColor.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        selected ? AppColor.accentPrimary : AppColor.borderDecorative,
                        lineWidth: selected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
        SelectionRow(label: "Rollstuhlnutzende", icon: "figure.roll", selected: true) {}
        SelectionRow(label: "Rollator", icon: "figure.walk", selected: false) {}
        SelectionRow(label: "Aktiv-Rollstuhl (Starrrahmen)", selected: false) {}
    }
    .padding()
    .background(AppColor.backgroundPrimary)
}