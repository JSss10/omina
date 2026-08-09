// Screen16_Summary.swift
// Omina – Onboarding Schritt 6/6: Profil-Zusammenfassung.
// Zeigt alle gewählten Werte und speichert das Profil in Supabase.

import SwiftUI

struct Screen16_Summary: View {
    let draft: DraftProfile
    let isSaving: Bool
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            if isSaving {
                ProgressView("Profil wird gespeichert…")
                    .tint(AppColor.accentPrimary)
                    .padding()
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColor.Status.blockedIcon)
                    Text(errorMessage)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.Status.blockedText)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppMetrics.Radius.field, style: .continuous)
                        .fill(AppColor.Status.blockedFill)
                )
            }

            SummarySection(title: "Mobilität") {
                SummaryRow(
                    label: "Kategorie",
                    value: draft.mobilityCategory?.displayName ?? "–"
                )
                SummaryRow(
                    label: "Rollstuhltyp",
                    value: draft.wheelchairSubtype?.displayName ?? "–"
                )
                if let type = draft.wheelchairType {
                    SummaryRow(
                        label: "Interne Kategorie",
                        value: type.displayName,
                        subdued: true
                    )
                }
            }

            SummarySection(title: "Masse") {
                SummaryRow(label: "Breite", value: "\(draft.widthCm) cm")
                SummaryRow(label: "Höhe (sitzend)", value: "\(draft.heightCm) cm")
                SummaryRow(label: "Sitzhöhe", value: "\(draft.seatHeightCm) cm")
                SummaryRow(label: "Länge", value: "\(draft.lengthCm) cm")
                SummaryRow(label: "Gewicht", value: "\(draft.weightKg) kg")
            }

            SummarySection(title: "Fähigkeiten") {
                SummaryRow(label: "Tempo",
                           value: String(format: "%.1f km/h", draft.travelSpeedKmh))
                SummaryRow(label: "Max. Steigung", value: "\(Int(draft.maxIncline)) %")
                SummaryRow(label: "Max. Bordsteinhöhe",
                           value: String(format: "%.1f cm", draft.maxCurbHeight))
                SummaryRow(label: "Untergrund", value: draft.surfaceTolerance.displayName)
                SummaryRow(label: "Manövrier-Spielraum",
                           value: "+\(draft.maneuverBufferCm) cm")
            }

            SummarySection(title: "Unterstützung") {
                SummaryRow(label: "Begleitung", value: draft.companionStatus.displayName)
                if draft.companionStatus != .alwaysAlone {
                    SummaryRow(
                        label: "Mit Begleitung",
                        value: "+\(Int(draft.companionInclineBonus)) % / +\(Int(draft.companionCurbBonus)) cm",
                        subdued: true
                    )
                }
                SummaryRow(label: "Eurokey", value: draft.hasEurokey ? "Ja" : "Nein")
            }

            Text("Du kannst dein Profil später in den Einstellungen jederzeit anpassen.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}

// MARK: - Display Helpers

private struct SummarySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.bottom, AppMetrics.Space.s)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .fill(AppColor.surfaceTinted)
            )
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    var subdued: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(subdued ? AppColor.textSecondary : AppColor.textPrimary)
            Spacer()
            Text(value)
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(subdued ? AppColor.textSecondary : AppColor.textPrimary)
        }
        .padding(.horizontal, AppMetrics.Space.m)
        .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
        .overlay(
            Rectangle()
                .fill(AppColor.borderDecorative)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

// MARK: - Display Name Extensions (nur für Summary-View)

extension MobilityCategory {
    var displayName: String {
        switch self {
        case .wheelchair:         return "Rollstuhl"
        case .walkingDisability:  return "Gehbehinderung"
        case .rollator:           return "Rollator"
        case .visualImpairment:   return "Sehbehinderung"
        case .blind:              return "Blindheit"
        case .hearingImpairment:  return "Hörbehinderung"
        case .deaf:               return "Gehörlosigkeit"
        case .stroller:           return "Kinderwagen"
        case .elderly:            return "Altersbedingt"
        case .none:               return "Ohne Einschränkung"
        }
    }
}

extension WheelchairType {
    var displayName: String {
        switch self {
        case .manual:        return "Manuell"
        case .emotion:       return "Manuell mit Zusatzantrieb"
        case .joystick:      return "Elektro (Joystick)"
        case .electric:      return "Elektro"
        case .stairClimbing: return "Treppensteiger"
        }
    }
}

extension SurfaceTolerance {
    var displayName: String {
        switch self {
        case .smoothOnly: return "Nur glatte Beläge"
        case .fineCobble: return "Kleines Kopfsteinpflaster OK"
        case .almostAll:  return "Fast alles"
        }
    }
}

extension CompanionStatus {
    var displayName: String {
        switch self {
        case .alwaysAlone: return "Immer allein"
        case .sometimes:   return "Manchmal begleitet"
        case .usually:     return "Meistens begleitet"
        }
    }
}