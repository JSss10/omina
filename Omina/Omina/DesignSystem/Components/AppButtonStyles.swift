// AppButtonStyles.swift
// Omina
//
// Button-Stile gemäss Styleguide v1.0 (§4.1 Buttons).
// Primäraktionen 56 pt hoch, Radius 14, gedrückter Zustand Violett 900.
// Der Fokusindikator ist Teil jeder Komponente, nicht ein nachträglicher Zusatz.

import SwiftUI

/// Primäraktion: gefüllt in Akzentfarbe, Text in OnAccent.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundColor(AppColor.onAccent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: AppMetrics.Touch.primary)
            .padding(.horizontal, AppMetrics.Space.l)
            .background(configuration.isPressed ? AppColor.accentPressed : AppColor.accentPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
    }
}

/// Sekundäraktion: Umriss in Akzentfarbe auf transparentem Grund.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundColor(AppColor.accentPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: AppMetrics.Touch.primary)
            .padding(.horizontal, AppMetrics.Space.l)
            .background(
                configuration.isPressed ? AppColor.accentPrimary.opacity(0.1) : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(AppColor.accentPrimary, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
    }
}

/// Zurückhaltende Aktion: getönte Fläche (Violett 100), Text in Akzentfarbe.
struct QuietButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundColor(AppColor.accentPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: AppMetrics.Touch.primary)
            .padding(.horizontal, AppMetrics.Space.l)
            .background(
                AppColor.Violet.v100.opacity(configuration.isPressed ? 0.7 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// Primäraktion (gefüllt). Benennt immer die Aktion («Route starten», nie «OK»).
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func appPrimary(fullWidth: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(fullWidth: fullWidth) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    /// Sekundäraktion (Umriss).
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func appSecondary(fullWidth: Bool) -> SecondaryButtonStyle { SecondaryButtonStyle(fullWidth: fullWidth) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    /// Zurückhaltende Aktion (getönt).
    static var appQuiet: QuietButtonStyle { QuietButtonStyle() }
    static func appQuiet(fullWidth: Bool) -> QuietButtonStyle { QuietButtonStyle(fullWidth: fullWidth) }
}
