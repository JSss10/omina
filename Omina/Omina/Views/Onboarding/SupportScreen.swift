// Screen15_Support.swift
// Omina – Onboarding Schritt 7/8: Unterstützung / Begleitung.
// Aufbau nach Entwurf: getönte Auswahlkarten mit Symbol, Titel und
// Erläuterung, darunter der Hinweistext und die Eurokey-Karte mit Schalter.
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
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
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
                    .padding(.top, AppMetrics.Space.s)
            }

            Text(footerText)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppMetrics.Space.s)

            eurokeyToggle
        }
    }

    // Eurokey-Besitz: schaltet abgeschlossene Eurokey-WCs als zugänglich frei.
    private var eurokeyToggle: some View {
        Toggle(isOn: $draft.hasEurokey) {
            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                Text("Ich besitze einen Eurokey")
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Viele Behinderten-WCs in der Schweiz sind mit dem Eurokey zugänglich.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppColor.accentPrimary)
        .padding(AppMetrics.Space.m)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                .fill(AppColor.surfaceTinted)
        )
    }

    private var footerText: String {
        if draft.companionStatus == .alwaysAlone {
            return "Alle Schwellenwerte gelten unverändert – so wie du sie in den Fähigkeiten eingestellt hast."
        }
        return "Mit Begleitperson hebt die App deine Schwellenwerte an: +\(Int(draft.companionInclineBonus)) % max. Steigung und +\(Int(draft.companionCurbBonus)) cm max. Bordsteinhöhe. Stell ein, wie viel deine Begleitung realistisch zusätzlich schafft."
    }

    // MARK: - Individuelle Begleit-Boni

    private var companionBonusCard: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                Image(systemName: "plusminus.circle")
                    .font(.title3)
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 28)
                Text("Wie viel hilft deine Begleitung?")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
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
        .padding(AppMetrics.Space.m)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                .fill(AppColor.surfaceTinted)
        )
    }
}

/// Auswahlkarte mit Symbol, Titel und Erläuterung (Entwurf Schritt 6).
private struct SupportCard: View {
    let icon: String
    let label: String
    let hint: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textBrand)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                    Text(label)
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(hint)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppMetrics.Space.s)

                if selected {
                    SelectionMark(selected: true)
                }
            }
            .padding(AppMetrics.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .fill(AppColor.surfaceTinted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(
                        selected ? AppColor.accentPrimary : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}