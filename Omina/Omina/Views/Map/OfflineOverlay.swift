// OfflineOverlay.swift
// Omina
//
// Schlanker Top-Banner, der über der Karte erscheint, sobald keine
// Netzwerkverbindung mehr da ist. Zeigt dem User, dass aktuell nur noch
// die zuletzt geladenen Daten sichtbar sind.

import SwiftUI

struct OfflineOverlay: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline – letzte geladene Daten werden angezeigt")
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.yellow.opacity(0.95), in: Capsule())
        .foregroundStyle(.black)
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
    }
}
