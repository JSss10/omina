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

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .frame(height: 56)
        .onAppear { isFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bestätigungscode, \(code.count) von \(length) Ziffern eingegeben")
    }

    private func digitBox(at index: Int) -> some View {
        let digits = Array(code)
        let isActive = isFocused && index == min(code.count, length - 1)

        return Text(index < digits.count ? String(digits[index]) : " ")
            .font(.title2.monospacedDigit().bold())
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.accentColor : Color(.systemGray4),
                            lineWidth: isActive ? 2 : 0.5)
            )
    }
}