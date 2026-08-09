// OnboardingNumberField.swift
// Omina – Wiederverwendbares Zahlen-Eingabefeld fürs Onboarding.
//
// Ersetzt die früheren Slider mit festen Ober-/Untergrenzen: Alle Werte,
// die beim Onboarding erfasst werden, sind frei zwischen 0 und unendlich
// eingebbar. Negative Eingaben werden auf 0 geklemmt, eine feste
// Obergrenze gibt es nicht. Deutsche Dezimaltrennung (Komma) wird
// akzeptiert.

import SwiftUI

struct OnboardingNumberField: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let unit: String
    let hint: String
    /// Ganze Zahlen (z. B. cm/kg) → keine Nachkommastellen.
    var isInteger: Bool = true
    /// Optionales Präfix vor dem Wert (z. B. „+“ für Begleit-Boni).
    var prefix: String = ""

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 28)
                Text(label)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    if !prefix.isEmpty {
                        Text(prefix)
                            .font(AppTypography.headline.monospacedDigit())
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    TextField("0", text: $text)
                        .keyboardType(isInteger ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppTypography.headline.monospacedDigit())
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(width: 64)
                        .textFieldStyle(.plain)
                        .compactFieldChrome()
                        .focused($focused)
                        .toolbar {
                            // Zahlentastatur hat keine Eingabetaste – „Fertig“
                            // schliesst sie. Erscheint nur beim fokussierten Feld.
                            if focused {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Fertig") { focused = false }
                                }
                            }
                        }
                    Text(unit)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            Text(hint)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                .fill(AppColor.surfaceTinted)
        )
        .onAppear { text = formatted(value) }
        // Externe Änderungen (z. B. Defaults aus dem Rollstuhltyp) übernehmen,
        // solange das Feld nicht gerade bearbeitet wird.
        .onChange(of: value) { _, newValue in
            if !focused { text = formatted(newValue) }
        }
        .onChange(of: text) { _, newText in
            value = parse(newText)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = formatted(value) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(prefix)\(formatted(value)) \(unit)")
    }

    /// Parst die Eingabe (Komma oder Punkt), klemmt auf ≥ 0, keine Obergrenze.
    private func parse(_ raw: String) -> Double {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else { return 0 }
        let clamped = max(0, parsed)
        return isInteger ? clamped.rounded() : clamped
    }

    private func formatted(_ value: Double) -> String {
        if isInteger {
            return String(Int(value.rounded()))
        }
        // Halbe Schritte lesbar (z. B. „3“ statt „3.0“, „3.5“ bleibt).
        return value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}