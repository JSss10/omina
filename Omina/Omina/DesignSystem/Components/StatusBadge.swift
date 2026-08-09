// StatusBadge.swift
// Omina
//
// Status-Badge gemäss Styleguide v1.0 (§2.3 Barriere-Semantik).
// Vierfach codiert (P2): Farbe + Form + Symbol + Text. Bleibt auch in
// Graustufen und bei Farbfehlsichtigkeit eindeutig unterscheidbar.

import SwiftUI

struct StatusBadge: View {
    let status: POIAccessStatus
    /// Kurzform («eingeschränkt») statt der vollen Beschreibung.
    var short: Bool = false

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            Image(systemName: status.symbolName)
                .font(.system(size: 18, weight: .semibold))
            Text(short ? status.shortLabel : status.label)
                .font(AppTypography.headline)
        }
        .foregroundColor(status.textColor)
        .padding(.horizontal, AppMetrics.Space.m)
        .padding(.vertical, AppMetrics.Space.s + 1)
        .background(status.fillColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
        StatusBadge(status: .accessible)
        StatusBadge(status: .limited)
        StatusBadge(status: .notAccessible)
        StatusBadge(status: .unknown)
    }
    .padding()
    .background(AppColor.backgroundPrimary)
}
