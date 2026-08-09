// Screen14_Abilities.swift
// Omina – Onboarding Schritt 4/6: Persönliche Fähigkeiten.
// Max. Steigung, max. Bordsteinhöhe, Untergrund-Toleranz. Werte sind frei
// zwischen 0 und unendlich eingebbar; Defaults kommen aus dem gewählten
// WheelchairType (Screen 1.2).

import SwiftUI

struct Screen14_Abilities: View {
    @Binding var draft: DraftProfile

    var body: some View {
        VStack(spacing: 20) {
            // MARK: Steigung
            OnboardingNumberField(
                icon: "triangle",
                label: "Maximale Steigung",
                value: $draft.maxIncline,
                unit: "%",
                hint: "Welche Steigung schaffst du noch komfortabel? (SIA-Norm: 9 %)"
            )

            // MARK: Bordstein
            OnboardingNumberField(
                icon: "square.stack.3d.up",
                label: "Maximale Bordsteinhöhe",
                value: $draft.maxCurbHeight,
                unit: "cm",
                hint: "Welche Kante überwindest du allein? (abgesenkt: ca. 3 cm)",
                isInteger: false
            )

            // MARK: Eigenes Tempo
            VStack(alignment: .leading, spacing: 10) {
                OnboardingNumberField(
                    icon: "speedometer",
                    label: "Dein Tempo",
                    value: $draft.travelSpeedKmh,
                    unit: "km/h",
                    hint: "Wie schnell bist du normalerweise unterwegs? (Handrollstuhl ca. 3–4 km/h, Elektrorollstuhl ca. 6 km/h)",
                    isInteger: false
                )

                Text("Fahrzeit und Ankunftszeit einer Route werden mit deinem Tempo berechnet – nicht mit dem Fussgänger-Tempo der Karten-Dienste.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            // MARK: Manövrier-Spielraum
            VStack(alignment: .leading, spacing: 10) {
                OnboardingNumberField(
                    icon: "arrow.left.and.right.square",
                    label: "Manövrier-Spielraum",
                    value: Binding(
                        get: { Double(draft.maneuverBufferCm) },
                        set: { draft.maneuverBufferCm = Int($0.rounded()) }
                    ),
                    unit: "cm",
                    hint: "Wie viel Platz brauchst du zusätzlich zur Rollstuhlbreite, um eine Engstelle sicher zu passieren? (empfohlen: 10 cm)",
                    prefix: "+"
                )

                Text("Bei Engstellen warnt dich die App, wenn der Durchgang schmaler ist als \(draft.widthCm + draft.maneuverBufferCm) cm (Breite + Spielraum).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            // MARK: Untergrund
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "road.lanes")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Text("Untergrund-Toleranz")
                        .font(.headline)
                }

                Text("Welche Beläge sind für dich passierbar?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(SurfaceTolerance.allCases, id: \.self) { tolerance in
                    SurfaceRow(
                        tolerance: tolerance,
                        selected: draft.surfaceTolerance == tolerance
                    ) {
                        draft.surfaceTolerance = tolerance
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}

private struct SurfaceRow: View {
    let tolerance: SurfaceTolerance
    let selected: Bool
    let action: () -> Void

    var label: String {
        switch tolerance {
        case .smoothOnly:  return "Nur glatte Beläge (Asphalt, Beton)"
        case .fineCobble:  return "Kleines Kopfsteinpflaster OK"
        case .almostAll:   return "Fast alles (auch grobes Pflaster)"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}