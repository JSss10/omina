// PhoneOrientationScreen.swift
// Omina – Onboarding Schritt 5/8: Handy-Ausrichtung für AR.
//
// Bewusst getrennt von den Körper-/Rollstuhlmassen (Schritt 4): Hier geht es
// nicht um Zahlen, sondern darum, WIE das iPhone im AR-Modus gehalten bzw.
// montiert wird. Eine gute Halterung und Ausrichtung sorgen dafür, dass der
// violette AR-Pfad ruhig auf dem Boden vor dir liegt und die Kamera den Weg
// erfasst. Rein informativ – keine Eingaben, «Weiter» ist immer möglich.

import SwiftUI

struct PhoneOrientationScreen: View {
    var body: some View {
        VStack(spacing: AppMetrics.Space.m) {
            Image(systemName: "arkit")
                .font(.system(size: 52))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, AppMetrics.Space.s)
                .accessibilityHidden(true)

            Text("Damit die AR-Navigation ruhig und genau bleibt, montiere und richte dein iPhone so aus:")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppMetrics.Space.s)

            VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                infoCard(
                    icon: "iphone.gen3",
                    title: "Handyhalterung nutzen",
                    detail: "Befestige das iPhone in einer Halterung am Rollstuhl – so hast du die Hände frei und das Bild wackelt nicht."
                )
                infoCard(
                    icon: "rectangle.portrait",
                    title: "Aufrecht im Hochformat",
                    detail: "Halte das iPhone hochkant und aufrecht. So passt der AR-Pfad zu deiner Blickrichtung."
                )
                infoCard(
                    icon: "camera.viewfinder",
                    title: "Leicht nach vorne neigen",
                    detail: "Neige das Gerät etwas nach vorne, damit die Kamera den Weg und den Boden direkt vor dir erfasst."
                )
                infoCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Kurz kalibrieren",
                    detail: "Beim Start langsam schwenken, bis sich die Umgebung eingemessen hat – dann liegt der Pfad stabil auf dem Boden."
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: AppMetrics.Space.xs / 2) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m - AppMetrics.Space.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                .fill(AppColor.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                .strokeBorder(AppColor.borderDecorative, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

#Preview {
    ScrollView {
        PhoneOrientationScreen()
            .padding()
    }
}