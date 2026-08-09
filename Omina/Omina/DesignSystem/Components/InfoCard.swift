// InfoCard.swift
// Omina
//
// Hinweiskarte gemäss Entwurf: getönte Fläche, links das Symbol in einem
// hellvioletten Kreis, rechts Titel und Erläuterung. Rein informativ – die
// Karte ist nicht antippbar und fasst für VoiceOver zu einer Aussage zusammen.
//
// Verwendet in den Schritten mit Erklärkarten (Handy-Ausrichtung) sowie auf
// den Screens Datenschutz und Zugriff erlauben.

import SwiftUI

struct InfoCard: View {
    let icon: String
    let title: String
    let detail: String

    /// Durchmesser des Symbolkreises; wächst mit Dynamic Type mit.
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.m) {
            Image(systemName: icon)
                .font(.system(size: badgeSize / 2.4, weight: .medium))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(AppColor.accentMuted))

            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textBrand)
                Text(detail)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                .fill(AppColor.surfaceTinted)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

#Preview {
    VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
        InfoCard(
            icon: "location.fill",
            title: "Standort",
            detail: "Zeigt Barrieren in deiner Nähe. Keine Ortung im Hintergrund."
        )
        InfoCard(
            icon: "camera.fill",
            title: "Kamera",
            detail: "Nur für die AR-Ansicht. Es werden keine Aufnahmen gespeichert."
        )
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}