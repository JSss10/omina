// PasswordStrengthBar.swift
// Omina
//
// Passwortstärke als fünf Segmente (Entwurf) mit Beschriftung darunter. Die
// Stufe steht immer auch als Wort da – die Balken allein wären eine reine
// Farb-/Mengencodierung und damit für viele Menschen nicht lesbar (WCAG 1.4.1).

import SwiftUI

/// Bewertung eines Passworts in fünf Stufen.
enum PasswordStrength: Int, CaseIterable {
    case none = 0
    case veryWeak = 1
    case weak = 2
    case medium = 3
    case strong = 4
    case veryStrong = 5

    /// Zählt erfüllte Kriterien: Länge (8 bzw. 12 Zeichen), Klein- und
    /// Grossbuchstaben, Ziffern, Sonderzeichen.
    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .none }

        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil,
           password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 1 }

        return PasswordStrength(rawValue: max(1, score)) ?? .veryWeak
    }

    var label: String {
        switch self {
        case .none:       return "noch kein Passwort"
        case .veryWeak:   return "sehr schwach"
        case .weak:       return "schwach"
        case .medium:     return "mittel"
        case .strong:     return "stark"
        case .veryStrong: return "sehr stark"
        }
    }
}

struct PasswordStrengthBar: View {
    let strength: PasswordStrength

    private let segments = PasswordStrength.allCases.count - 1

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            HStack(spacing: AppMetrics.Space.s) {
                ForEach(1...segments, id: \.self) { index in
                    Capsule()
                        .fill(AppColor.accentPrimary.opacity(index <= strength.rawValue ? 1 : 0.3))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.2), value: strength)
                }
            }

            Text("Passwortstärke: \(strength.label)")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.accentPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passwortstärke: \(strength.label)")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
        PasswordStrengthBar(strength: .weak)
        PasswordStrengthBar(strength: .strong)
        PasswordStrengthBar(strength: .veryStrong)
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}