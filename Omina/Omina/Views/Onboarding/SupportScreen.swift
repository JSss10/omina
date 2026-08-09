// Screen15_Support.swift
// Omina – Onboarding Schritt 5/6: Unterstützung / Begleitung.
// Beeinflusst effectiveMaxIncline und effectiveMaxCurb in der Barrierenlogik.

import SwiftUI

struct Screen15_Support: View {
    @Binding var draft: DraftProfile

    private let options: [(CompanionStatus, String, String, String)] = [
        (.alwaysAlone,
         "Ich bin immer allein unterwegs",
         "figure.roll",
         "Alle Barrieren werden auf Basis deiner persönlichen Werte bewertet."),
        (.sometimes,
         "Manchmal mit Begleitung",
         "figure.2",
         "Du kannst vor jeder Fahrt in den Einstellungen umschalten."),
        (.usually,
         "Meistens mit Begleitung",
         "figure.2.arms.open",
         "Barrieren werden mit deinen Begleitungs-Werten (unten einstellbar) bewertet.")
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(options, id: \.0) { status, label, icon, hint in
                SupportCard(
                    icon: icon,
                    label: label,
                    hint: hint,
                    selected: draft.companionStatus == status
                ) {
                    draft.companionStatus = status
                }
            }

            if draft.companionStatus != .alwaysAlone {
                companionBonusCard
            }

            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.top, 8)

            eurokeyToggle
        }
    }

    // Eurokey-Besitz: schaltet abgeschlossene Eurokey-WCs als zugänglich frei.
    private var eurokeyToggle: some View {
        Toggle(isOn: $draft.hasEurokey) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ich besitze einen Eurokey")
                    .font(.body.weight(.medium))
                Text("Viele Behinderten-WCs in der Schweiz sind mit dem Eurokey zugänglich.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.top, 4)
    }

    private var footerText: String {
        if draft.companionStatus == .alwaysAlone {
            return "Alle Schwellenwerte gelten unverändert – so wie du sie in den Fähigkeiten eingestellt hast."
        }
        return "Mit Begleitperson hebt die App deine Schwellenwerte an: +\(Int(draft.companionInclineBonus)) % max. Steigung und +\(Int(draft.companionCurbBonus)) cm max. Bordsteinhöhe. Stell ein, wie viel deine Begleitung realistisch zusätzlich schafft."
    }

    // MARK: - Individuelle Begleit-Boni

    private var companionBonusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "plusminus.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                Text("Wie viel hilft deine Begleitung?")
                    .font(.headline)
            }

            OnboardingNumberField(
                icon: "triangle",
                label: "Zusätzliche Steigung",
                value: $draft.companionInclineBonus,
                unit: "%",
                hint: "Wie viel mehr Steigung schafft ihr gemeinsam?",
                prefix: "+"
            )

            OnboardingNumberField(
                icon: "square.stack.3d.up",
                label: "Zusätzliche Bordsteinhöhe",
                value: $draft.companionCurbBonus,
                unit: "cm",
                hint: "Wie viel höhere Kanten überwindet ihr gemeinsam?",
                prefix: "+"
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct SupportCard: View {
    let icon: String
    let label: String
    let hint: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}