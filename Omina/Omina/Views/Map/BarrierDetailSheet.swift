// BarrierDetailSheet.swift
// Omina
//
// Detail-Bottom-Sheet für eine Barriere.
// Zeigt Typ + Icon, formatierten Wert gegen persönliches Limit
// und eine Warum-Erklärung. Während einer aktiven Navigation (Liste
// "Barrieren auf der Route") zusätzlich: "Heute nicht machbar?" mit
// Alternativroute – für Barrieren, die je nach Tagesform (z. B. Hitze,
// Erschöpfung) gerade nicht bewältigbar sind, obwohl sie es sonst wären.

import SwiftUI

/// Kapselt die Alternativroute-Aktion als nominalen Sendable-Typ statt als
/// nackten Funktionswert: Beim Übergeben eines optionalen Funktionswerts
/// meldet der Compiler sonst fälschlich ein Sendable-Datenrennen.
struct AlternativeRouteAction: Sendable {
    let run: @MainActor @Sendable () async -> Bool
}

struct BarrierDetailSheet: View {
    let barrier: Barrier
    let profile: UserProfile
    /// Berechnet eine Route, die diese Barriere umgeht (nur während einer
    /// aktiven Navigation gesetzt). Rückgabe `true` = Route gefunden.
    var onFindAlternative: AlternativeRouteAction? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingFeedback = false
    @State private var feedbackSubmitted = false
    @State private var isFindingAlternative = false
    @State private var alternativeFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                comparison
                explanation
                alternativeSection
                feedbackButton
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingFeedback) {
            FeedbackFormView(barrier: barrier) {
                feedbackSubmitted = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(barrier.type.tint)
                    .frame(width: 56, height: 56)
                Image(systemName: barrier.type.symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(barrier.type.localizedLabel)
                    .font(.title2)
                    .bold()
                if let valueText = formattedValue {
                    Text(valueText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var comparison: some View {
        if let limitText = formattedLimit {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dein Limit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(limitText)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warum?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(explanationText)
                .font(.body)
        }
    }

    /// Tagesform-Sektion während einer aktiven Navigation: auch eine sonst
    /// passierbare Barriere kann heute zu viel sein (Hitze, wenig Kraft).
    /// Der Button berechnet die Route neu, so dass sie die Stelle umgeht.
    @ViewBuilder
    private var alternativeSection: some View {
        if let onFindAlternative {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heute nicht machbar?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Nicht jeder Tag ist gleich: Bei Hitze oder wenig Kraft kann eine Barriere zu viel sein, die sonst kein Problem ist. Lass dir eine Route berechnen, die diese Stelle umgeht.")
                    .font(.body)

                Button {
                    findAlternative(onFindAlternative)
                } label: {
                    HStack(spacing: 8) {
                        if isFindingAlternative {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        Text(isFindingAlternative ? "Alternativroute wird berechnet…" : "Alternativroute anzeigen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isFindingAlternative)

                if alternativeFailed {
                    Label(
                        "Keine Alternativroute gefunden – diese Stelle lässt sich aktuell nicht umgehen.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppColor.Status.limitedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func findAlternative(_ action: AlternativeRouteAction) {
        alternativeFailed = false
        isFindingAlternative = true
        Task { @MainActor in
            let success = await action.run()
            isFindingAlternative = false
            if success {
                dismiss()
            } else {
                alternativeFailed = true
            }
        }
    }

    @ViewBuilder
    private var feedbackButton: some View {
        if feedbackSubmitted {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Feedback gesendet – danke!")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                showingFeedback = true
            } label: {
                Label("Stimmt nicht mehr?", systemImage: "exclamationmark.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Formatting

    private var formattedValue: String? {
        switch barrier.type {
        case .steps:
            return barrier.value.map { "\(Int($0)) Stufen" }
        case .curb, .curbMissing:
            return barrier.value.map { "\(Int($0)) cm hoch" }
        case .incline:
            return barrier.value.map { "\(Int($0)) %" }
        case .narrow:
            return barrier.value.map { "\(Int($0)) cm Durchgang" }
        case .surface:
            return barrier.subtype.map(BarrierType.localizedSurface)
        case .temporary:
            return nil
        }
    }

    private var formattedLimit: String? {
        switch barrier.type {
        case .steps:
            return profile.wheelchairType.canClimbStairs ? "Du kannst Stufen überwinden" : "Stufen sind nicht passierbar"
        case .curb, .curbMissing:
            return "Bis \(Int(profile.effectiveMaxCurb)) cm Bordsteinhöhe"
        case .incline:
            return "Bis \(Int(profile.effectiveMaxIncline)) % Steigung"
        case .narrow:
            return "Mindestens \(profile.effectiveWidthNeeded) cm Durchgang"
        case .surface:
            return "Oberflächentoleranz: \(surfaceToleranceText(profile.surfaceTolerance))"
        case .temporary:
            return nil
        }
    }

    private func surfaceToleranceText(_ tolerance: SurfaceTolerance) -> String {
        switch tolerance {
        case .smoothOnly:  return "nur glatt"
        case .fineCobble:  return "feines Kopfsteinpflaster"
        case .almostAll:   return "fast alles"
        }
    }

    private var explanationText: String {
        shouldWarn(barrier: barrier, profile: profile) ? personalReason : neutralReason
    }

    private var personalReason: String {
        switch barrier.type {
        case .steps:
            return "Stufen sind mit deinem Rollstuhltyp nicht überwindbar."
        case .curb:
            return "Der Bordstein ist höher als das, was du sicher überwinden kannst."
        case .curbMissing:
            return "An dieser Stelle fehlt eine Bordsteinabsenkung – Übergang nicht garantiert befahrbar."
        case .incline:
            return "Die Steigung übersteigt das, was dein Rollstuhl bewältigen kann."
        case .surface:
            return "Diese Oberfläche liegt außerhalb deiner gewählten Toleranz."
        case .narrow:
            return "Der Durchgang ist schmaler als die Breite, die du brauchst."
        case .temporary:
            return "Hier ist der Weg aktuell blockiert."
        }
    }

    private var neutralReason: String {
        switch barrier.type {
        case .steps:        return "Diese Stufen liegen innerhalb dessen, was du bewältigen kannst."
        case .curb:         return "Der Bordstein liegt unter deinem Limit."
        case .curbMissing:  return "Fehlende Absenkung – siehe Detail."
        case .incline:      return "Die Steigung liegt unter deinem Limit."
        case .surface:      return "Die Oberfläche passt zu deiner gewählten Toleranz."
        case .narrow:       return "Der Durchgang ist breit genug für dich."
        case .temporary:    return "Hier ist der Weg aktuell blockiert."
        }
    }
}