// BarrierDetailSheet.swift
// Omina
//
// Detail-Bottom-Sheet für eine Barriere, Aufbau nach Entwurf: Kopfzeile mit
// Teilen, Titel «Barriere» und Schliessen; darunter Typ und Distanz, der Wert
// als Unterzeile, dann die Erklärung und – während einer aktiven Navigation –
// die Alternativroute. Zuunterst der Weg, eine veraltete Meldung zu korrigieren.
//
// Die Alternativroute gibt es für Barrieren, die je nach Tagesform (Hitze,
// Erschöpfung) gerade nicht bewältigbar sind, obwohl sie es sonst wären.

import SwiftUI
import CoreLocation

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
        VStack(spacing: 0) {
            SheetHeader(
                title: "Barriere",
                onClose: { dismiss() },
                leading: AnyView(shareButton)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    header

                    Rectangle()
                        .fill(AppColor.borderDecorative)
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    explanation
                    comparison
                    alternativeHint
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.s)
                .padding(.bottom, AppMetrics.Space.m)
            }

            footer
        }
        .background(AppColor.surfaceOverlay)
        .presentationBackground(AppColor.surfaceOverlay)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingFeedback) {
            FeedbackFormView(barrier: barrier) {
                feedbackSubmitted = true
            }
        }
    }

    // MARK: - Kopf

    private var shareButton: some View {
        ShareLink(item: shareText) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .background(AppColor.surfaceTinted, in: Circle())
        }
        .accessibilityLabel("Barriere teilen")
    }

    private var shareText: String {
        var parts = [barrier.type.localizedLabel]
        if let value = formattedValue { parts.append(value) }
        parts.append("https://maps.apple.com/?ll=\(barrier.latitude),\(barrier.longitude)")
        return parts.joined(separator: "\n")
    }

    /// Typ gross, rechts die Distanz, darunter der Messwert (Entwurf).
    private var header: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.Space.m) {
                Text(barrier.type.localizedLabel)
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColor.textBrand)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppMetrics.Space.s)

                if let distance = distanceText {
                    HStack(spacing: AppMetrics.Space.s) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 15, weight: .regular))
                            .rotationEffect(.degrees(45))
                        Text(distance)
                            .font(AppTypography.body)
                            .monospacedDigit()
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(distance + " entfernt")
                }
            }

            if let valueText = formattedValue {
                Text(valueText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    /// Distanz zur Barriere, sofern ein Standort vorliegt.
    private var distanceText: String? {
        guard let user = LocationService.shared.currentLocation else { return nil }
        let meters = user.distance(
            from: CLLocation(latitude: barrier.latitude, longitude: barrier.longitude)
        )
        return DistanceFormatter.string(fromMeters: meters)
    }

    // MARK: - Erklärung

    private var explanation: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Was dich hier erwartet")
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Text(explanationText)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Der eigene Grenzwert als Vergleich – macht nachvollziehbar, warum die
    /// Stelle für dieses Profil kritisch ist oder eben nicht.
    @ViewBuilder
    private var comparison: some View {
        if let limitText = formattedLimit {
            HStack(alignment: .top, spacing: AppMetrics.Space.m) {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppColor.accentMuted, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dein Limit")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textBrand)
                    Text(limitText)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(AppMetrics.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// Hinweis zur Tagesform – erklärt, wofür die Alternativroute gut ist.
    @ViewBuilder
    private var alternativeHint: some View {
        if onFindAlternative != nil {
            Text("Nicht jeder Tag ist gleich: Bei Hitze oder wenig Kraft kann eine Barriere zu viel sein, die sonst kein Problem ist. Die Alternativroute umgeht diese Stelle.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if alternativeFailed {
            HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.Status.limitedIcon)
                Text("Keine Alternativroute gefunden – diese Stelle lässt sich aktuell nicht umgehen.")
                    .foregroundStyle(AppColor.Status.limitedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppTypography.footnote)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Fusszeile

    /// Alternativroute als Hauptaktion, darunter die Korrekturmeldung – wie im
    /// Entwurf beide über die ganze Breite.
    private var footer: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            if let onFindAlternative {
                Button {
                    findAlternative(onFindAlternative)
                } label: {
                    if isFindingAlternative {
                        ProgressView()
                            .tint(AppColor.onAccent)
                    } else {
                        Text("Alternativroute anzeigen")
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(isFindingAlternative)
            }

            if feedbackSubmitted {
                HStack(spacing: AppMetrics.Space.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.Status.openIcon)
                    Text("Feedback gesendet – danke!")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppMetrics.Touch.primary)
                .accessibilityElement(children: .combine)
            } else {
                Button("Stimmt nicht mehr?") {
                    showingFeedback = true
                }
                .buttonStyle(.appQuiet(fullWidth: true))
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.surfaceOverlay)
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