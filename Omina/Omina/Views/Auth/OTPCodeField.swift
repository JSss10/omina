// OTPCodeField.swift
// Omina
//
// Mehrstelliges Code-Eingabefeld für E-Mail-Bestätigung und Code-Anmeldung.
// Ein verstecktes TextField hält den Wert; ein Kästchen pro Ziffer zeigt die
// Eingabe an, damit sie wie bei Apples eigenen Code-Feldern wirkt.
// Die Länge kommt von aussen (AppConfig.emailOTPCodeLength).

import SwiftUI

struct OTPCodeField: View {
    @Binding var code: String
    var length: Int = 6
    var onComplete: (() -> Void)? = nil
    /// Meldet, ob das Feld gerade bearbeitet wird – die Fusszeile zeigt dann
    /// die Bestätigen-Aktion über der Tastatur (Entwurf).
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    // Nur Ziffern, maximal `length` Stellen
                    let filtered = String(newValue.filter(\.isNumber).prefix(length))
                    if filtered != newValue {
                        code = filtered
                    }
                    if filtered.count == length {
                        isFocused = false
                        onComplete?()
                    }
                }

            HStack(spacing: AppMetrics.Space.s) {
                ForEach(0..<length, id: \.self) { index in
                    digitSlot(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in onFocusChange?(focused) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bestätigungscode, \(code.count) von \(length) Ziffern eingegeben")
    }

    /// Eine Stelle als getönter Kreis (Entwurf). Die Stelle, die als Nächstes
    /// dran ist, trägt den gefüllten Punkt – so sieht man ohne Cursor, wo man
    /// gerade steht.
    private func digitSlot(at index: Int) -> some View {
        let digits = Array(code)
        let isNext = isFocused && index == min(code.count, length - 1) && index >= digits.count

        return ZStack {
            Circle()
                .fill(AppColor.surfaceTinted)

            if index < digits.count {
                Text(String(digits[index]))
                    .font(AppTypography.title3.monospacedDigit())
                    .foregroundStyle(AppColor.textBrand)
                    .minimumScaleFactor(0.6)
            } else if isNext {
                Circle()
                    .fill(AppColor.textBrand)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}