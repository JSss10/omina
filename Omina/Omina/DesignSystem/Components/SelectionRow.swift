// SelectionRow.swift
// Omina
//
// Auswählbare Zeile (Single-Choice) gemäss Entwurf: violett getönte Karte,
// optionales Leit-Icon, rechts der Auswahlpunkt – gepunkteter Ring, solange
// nichts gewählt ist, gefülltes Häkchen danach. Der ausgewählte Zustand trägt
// zusätzlich den Akzentrahmen, ist also nicht allein über die Farbe codiert
// (P2, Styleguide §2.3).
//
// Wird in den Onboarding-Auswahlschritten verwendet (Mobilitätskategorie,
// Rollstuhltyp) und hält die Auswahl überall gleich – Touch-Ziel >= 56 pt.

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
                        .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textBrand)
                        .frame(width: 28)
                }

                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: AppMetrics.Space.s)

                SelectionMark(selected: selected)
            }
            .padding(.horizontal, AppMetrics.Space.m + AppMetrics.Space.xs)
            .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
            .frame(minHeight: AppMetrics.Touch.primary)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .fill(AppColor.surfaceTinted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(
                        selected ? AppColor.accentPrimary : AppColor.borderDecorative,
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Auswahlpunkt

/// Auswahlmarke aus dem Entwurf: gepunkteter Ring (nicht gewählt) bzw.
/// gefülltes Häkchen (gewählt).
struct SelectionMark: View {
    let selected: Bool
    var size: CGFloat = 24

    var body: some View {
        Group {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppColor.onAccent, AppColor.accentPrimary)
            } else {
                Circle()
                    .strokeBorder(
                        AppColor.Violet.v500,
                        style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 3])
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
        SelectionRow(label: "Aktivrollstuhl", icon: "figure.roll", selected: true) {}
        SelectionRow(label: "Sportrollstuhl", icon: "figure.roll.runningpace", selected: false) {}
        SelectionRow(label: "Faltrollstuhl", selected: false) {}
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}