// AppButtonStyles.swift
// Omina
//
// Button-Stile gemäss Styleguide v1.0 (§4.1 Buttons).
// Primäraktionen 56 pt hoch, Radius 14, gedrückter Zustand Violett 900.
// Der Fokusindikator ist Teil jeder Komponente, nicht ein nachträglicher Zusatz.

import SwiftUI

/// Primäraktion: gefüllt in Akzentfarbe, Text in OnAccent. Inaktiv steht sie
/// – wie im Entwurf – gedämpft in Violett 300 mit dunkler Schrift, statt die
/// ganze Fläche transparent zu schalten.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, fullWidth: fullWidth)
    }

    // Eigene View, weil @Environment (hier: isEnabled) nur in einer View
    // aktualisiert wird, nicht direkt im ButtonStyle. Der Name darf nicht
    // "Body" lauten – das ist der Associated Type von ButtonStyle.
    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(AppTypography.headline)
                .foregroundColor(isEnabled ? AppColor.onAccent : AppColor.textBrand)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: AppMetrics.Touch.primary)
                .padding(.horizontal, AppMetrics.Space.l)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
        }

        private var fill: Color {
            guard isEnabled else { return AppColor.accentMuted }
            return configuration.isPressed ? AppColor.accentPressed : AppColor.accentPrimary
        }
    }
}

/// Sekundäraktion: Umriss im Markenviolett auf transparentem Grund (Entwurf:
/// "Zurück" neben der Primäraktion).
///
/// Die gedrückte Fläche kommt aus `surfaceTinted` und nicht aus der
/// Referenzstufe Violett 100: Die Palettenstufen haben keine Dunkel-Variante,
/// die Fläche bliebe im Dunkelmodus also hell – unter hellem Text.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundColor(AppColor.textBrand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: AppMetrics.Touch.primary)
            .padding(.horizontal, AppMetrics.Space.l)
            .background(
                configuration.isPressed ? AppColor.surfaceTinted.opacity(0.6) : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(AppColor.textBrand, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous))
    }
}

/// Zurückhaltende Aktion: getönte Fläche, Text in Akzentfarbe.
///
/// Die Fläche ist `surfaceTinted` (hell #EDE9FE · dunkel #241D3A) und nicht
/// die Referenzstufe Violett 100. Diese hat keine Dunkel-Variante: Im
/// Dunkelmodus stand die helle Akzentschrift (#C4B5FD) sonst auf hellem
/// Violett und war praktisch nicht zu lesen – so trägt der Button in beiden
/// Modi 7,5:1 bzw. 8,7:1.
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
                AppColor.surfaceTinted.opacity(configuration.isPressed ? 0.7 : 1)
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

// MARK: - Beschriftung mit Richtungspfeil

/// Beschriftung einer Navigations-Aktion mit Pfeil – links für Rückschritte,
/// rechts für Vorwärtsschritte (Entwurf der Onboarding-Fusszeile).
struct NavigationActionLabel: View {
    let title: String
    var direction: Direction = .forward

    enum Direction { case back, forward }

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            if direction == .back {
                Image(systemName: "chevron.left")
            }
            Text(title)
            if direction == .forward {
                Image(systemName: "chevron.right")
            }
        }
        .font(AppTypography.headline)
    }
}