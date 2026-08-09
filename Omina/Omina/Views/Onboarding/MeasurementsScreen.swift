// Screen13_Measurements.swift
// Omina – Onboarding Schritt 3/6: Masse (Breite, Höhe, Gewicht).
// Werte werden mit Defaults aus WheelchairType vorbelegt. Jeder Wert lässt
// sich per Slider grob einstellen; das Zahlenfeld daneben nimmt zusätzlich
// jeden Wert zwischen 0 und unendlich an (auch oberhalb des Slider-Endes).

import SwiftUI

struct Screen13_Measurements: View {
    @Binding var draft: DraftProfile

    var body: some View {
        VStack(spacing: 20) {
            MeasurementSlider(
                icon: "arrow.left.and.right",
                label: "Rollstuhlbreite",
                value: intBinding(\.widthCm),
                sliderMax: 150,
                unit: "cm",
                hint: "Gesamtbreite inklusive Räder und Antriebe"
            )

            MeasurementSlider(
                icon: "arrow.up.and.down",
                label: "Gesamthöhe (sitzend)",
                value: intBinding(\.heightCm),
                sliderMax: 250,
                unit: "cm",
                hint: "Wichtig für niedrige Durchgänge und Überdachungen"
            )

            MeasurementSlider(
                icon: "arrow.up.to.line.compact",
                label: "Sitzhöhe",
                value: intBinding(\.seatHeightCm),
                sliderMax: 120,
                unit: "cm",
                hint: "Oberkante Sitzfläche inkl. Kissen ab Boden – bestimmt deine Augenhöhe für den AR-Pfad"
            )

            MeasurementSlider(
                icon: "arrow.forward.to.line",
                label: "Gesamtlänge",
                value: intBinding(\.lengthCm),
                sliderMax: 250,
                unit: "cm",
                hint: "Inklusive Fussstützen – relevant für Lifte und Wendeflächen"
            )

            MeasurementSlider(
                icon: "scalemass",
                label: "Gesamtgewicht",
                value: intBinding(\.weightKg),
                sliderMax: 300,
                unit: "kg",
                hint: "Rollstuhl + Person (relevant für Rampen und Lifte)"
            )
        }
    }

    /// Verbindet ein Int-Feld des Drafts mit dem Double-basierten Eingabefeld.
    private func intBinding(_ keyPath: WritableKeyPath<DraftProfile, Int>) -> Binding<Double> {
        Binding(
            get: { Double(draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}

/// Slider (0 … sliderMax) für die grobe Einstellung, kombiniert mit einem
/// editierbaren Zahlenfeld. Das Zahlenfeld akzeptiert jeden Wert ≥ 0 – auch
/// oberhalb des Slider-Endes –, sodass die Eingabe faktisch bis unendlich
/// reicht. Der Slider-Thumb bleibt in diesem Fall am rechten Anschlag.
private struct MeasurementSlider: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let sliderMax: Double
    var step: Double = 1
    let unit: String
    let hint: String

    @State private var text: String = ""
    @FocusState private var focused: Bool

    /// Auf [0, sliderMax] geklemmtes Binding für den Slider, damit getippte
    /// Werte oberhalb des Endes den Slider nicht sprengen; der freie Wert
    /// bleibt im `value`-Binding erhalten.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { min(max(value, 0), sliderMax) },
            set: { value = $0 }
        )
    }

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
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppTypography.headline.monospacedDigit())
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(width: 56)
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
            Slider(value: sliderValue, in: 0...sliderMax, step: step)
                .tint(AppColor.accentPrimary)
            Text(hint)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                .fill(AppColor.surfaceTinted)
        )
        .onAppear { text = String(Int(value.rounded())) }
        // Externe Änderungen (Defaults aus dem Rollstuhltyp, Slider-Drag)
        // übernehmen, solange das Feld nicht gerade bearbeitet wird.
        .onChange(of: value) { _, newValue in
            if !focused { text = String(Int(newValue.rounded())) }
        }
        .onChange(of: text) { _, newText in
            value = parse(newText)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = String(Int(value.rounded())) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value.rounded())) \(unit)")
    }

    /// Parst die Eingabe, klemmt auf ≥ 0, keine Obergrenze.
    private func parse(_ raw: String) -> Double {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else { return 0 }
        return max(0, parsed).rounded()
    }
}