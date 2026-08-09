// AppTextField.swift
// Omina
//
// Eingabefeld gemäss Entwurf: weisse Fläche, feiner Rahmen, Radius 14 und
// die Beschriftung als Platzhalter im Feld selbst – es gibt keine Label-Zeile
// darüber. Damit VoiceOver das Feld trotzdem benennt, wandert der Platzhalter
// zusätzlich in das Accessibility-Label; er verschwindet nur optisch, sobald
// etwas eingegeben ist.
//
// Styling ausschliesslich über Tokens (AppColor, AppTypography, AppMetrics).

import SwiftUI

struct AppTextField: View {
    /// Beschriftung im Feld – zugleich das Accessibility-Label.
    let placeholder: String
    @Binding var text: String

    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrection: Bool = true
    /// Passwortfeld: Eingabe verdeckt.
    var isSecure: Bool = false
    /// Auge-Schaltfläche zum Ein-/Ausblenden des Passworts (Entwurf 0.2).
    var showsRevealToggle: Bool = false

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(AppColor.textBrand)
                        .allowsHitTesting(false)
                }
                field
            }

            if showsRevealToggle {
                revealToggle
            }
        }
        .font(AppTypography.body)
        .appFieldChrome()
    }

    @ViewBuilder
    private var field: some View {
        Group {
            if isSecure && !isRevealed {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(AppColor.textPrimary)
        .tint(AppColor.accentPrimary)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled(!autocorrection)
        .accessibilityLabel(placeholder)
    }

    private var revealToggle: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(AppColor.accentPrimary))
                // Sichtbar bleibt der Kreis klein, antippbar ist er in voller
                // Zielgrösse (WCAG 2.5.5).
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "Passwort verbergen" : "Passwort anzeigen")
    }
}

// MARK: - Feld-Rahmen

/// Rahmen und Fläche eines Eingabefelds. Steht als Modifier bereit, damit auch
/// zusammengesetzte Felder (Vorwahl + Nummer, Auswahlfelder) gleich aussehen.
struct AppFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppMetrics.Space.m + AppMetrics.Space.xs)
            .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
            .frame(minHeight: AppMetrics.Touch.minimum + AppMetrics.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .fill(AppColor.backgroundPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(AppColor.borderDecorative, lineWidth: 1)
            )
    }
}

/// Kompakte Variante für kleine Zahlenfelder in den Karten (Masse,
/// Fähigkeiten): gleiche Farben, aber flacher, damit die Kartenzeile ihre
/// Höhe behält.
struct CompactFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppMetrics.Space.s)
            .padding(.vertical, AppMetrics.Space.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.chip, style: .continuous)
                    .fill(AppColor.backgroundPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.chip, style: .continuous)
                    .strokeBorder(AppColor.borderDecorative, lineWidth: 1)
            )
    }
}

extension View {
    /// Fläche und Rahmen eines Eingabefelds (Entwurf).
    func appFieldChrome() -> some View {
        modifier(AppFieldChrome())
    }

    /// Flache Feldfläche für Zahlenfelder in Karten.
    func compactFieldChrome() -> some View {
        modifier(CompactFieldChrome())
    }
}

#Preview {
    @Previewable @State var name = ""
    @Previewable @State var phone = ""
    @Previewable @State var password = "geheim123"

    VStack(spacing: AppMetrics.Space.m) {
        AppTextField(placeholder: "Vorname", text: $name)
        AppTextField(
            placeholder: "Passwort",
            text: $password,
            isSecure: true,
            showsRevealToggle: true
        )
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Text("+ 41")
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(AppColor.textBrand)
                .appFieldChrome()
                .frame(width: 88)
            AppTextField(placeholder: "79 000 00 00", text: $phone, keyboardType: .phonePad)
        }
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}