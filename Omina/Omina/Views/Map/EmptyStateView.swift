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
                .foregroundStyle(.secondary)

            Text("Keine Barrieren in der Nähe")
                .font(.headline)

            Text("Erweitere den Suchradius oder bewege dich in ein anderes Gebiet.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                onOpenFilter()
            } label: {
                Label("Filter öffnen", systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 6)
        .padding(.horizontal, 24)
    }
}
