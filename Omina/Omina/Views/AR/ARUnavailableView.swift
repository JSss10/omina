// ARUnavailableView.swift
// Omina
//
// AR-Fehler-State. Dunkler Vollbild-Screen mit Grund und
// Rückweg zur Karte; die Karte bleibt immer als Fallback nutzbar.

import SwiftUI

struct ARUnavailableView: View {
    let reason: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "exclamationmark.square")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.red)

                Text("AR nicht verfügbar")
                    .font(.title)
                    .bold()
                    .foregroundStyle(.white)

                Text(reason)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Weitere Gründe: ARGeo nicht unterstützt · Kamera verweigert · Gerät ohne ARKit".uppercased())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    onBack()
                } label: {
                    Text("Zurück zur Karte")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Einstellungen öffnen")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .underline()
                }
                .padding(.bottom, 40)
            }
        }
    }
}