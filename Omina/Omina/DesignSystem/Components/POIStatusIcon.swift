// POIStatusIcon.swift
// Omina
//
// Kleines rundes Status-Icon für POI-Marker (Karte + AR): SF-Symbol mit
// Grundform (Häkchen, Warndreieck, Kreuz) statt eines reinen Farbpunkts.
// P2 des Styleguides: Farbe trägt nie allein Information.

import SwiftUI

struct POIStatusIcon: View {
    let status: POIAccessStatus
    /// Durchmesser des weissen Trägerkreises; das Symbol skaliert mit.
    var diameter: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.2), radius: 1)
            Image(systemName: status.symbolName)
                .font(.system(size: diameter - 3, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, status.tint)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        POIStatusIcon(status: .accessible)
        POIStatusIcon(status: .limited)
        POIStatusIcon(status: .notAccessible)
        POIStatusIcon(status: .unknown)
        POIStatusIcon(status: .accessible, diameter: 22)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}