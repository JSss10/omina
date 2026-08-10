// EmptyStateView.swift
// Omina
//
// Compact centered card, der über die Karte gelegt wird, wenn der Load durch
// ist und keine Barrieren zurückgekommen sind. Erlaubt direkt eine
// Folge-Aktion (Filter öffnen, um den Radius zu vergrößern).

import SwiftUI

struct EmptyStateView: View {
    let onOpenFilter: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.accentPrimary)

            Text("Keine Barrieren in der Nähe")
                .font(AppTypography.headline)
                .foregroundStyle(AppColor.textBrand)

            Text("Erweitere den Suchradius oder bewege dich in ein anderes Gebiet.")
                .font(AppTypography.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.textSecondary)

            Button("Filter öffnen") {
                onOpenFilter()
            }
            .buttonStyle(.appQuiet(fullWidth: true))
            .padding(.top, AppMetrics.Space.xs)
        }
        .padding(AppMetrics.Space.l)
        .frame(maxWidth: 320)
        .background(
            AppColor.backgroundPrimary,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .shadow(radius: 6)
        .padding(.horizontal, 24)
    }
}