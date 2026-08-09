// PhoneOrientationScreen.swift
// Omina – Onboarding Schritt 8/8: Handy-Ausrichtung für AR.
//
// Aufbau nach Entwurf: Hinweiskarten mit Symbolkreis, Titel und Erläuterung,
// darunter am unteren Rand der zusammenfassende Absatz.
//
// Bewusst getrennt von den Körper-/Rollstuhlmassen: Hier geht es nicht um
// Zahlen, sondern darum, WIE das iPhone im AR-Modus gehalten bzw. montiert
// wird. Eine gute Halterung und Ausrichtung sorgen dafür, dass der violette
// AR-Pfad ruhig auf dem Boden vor dir liegt und die Kamera den Weg erfasst.
// Rein informativ – keine Eingaben, «Weiter» ist immer möglich.

import SwiftUI

struct PhoneOrientationScreen: View {
    var body: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            InfoCard(
                icon: "iphone.gen3",
                title: "Handyhalterung nutzen",
                detail: "Befestige das iPhone in einer Halterung am Rollstuhl – so hast du die Hände frei und das Bild wackelt nicht."
            )
            InfoCard(
                icon: "rectangle.portrait",
                title: "Aufrecht im Hochformat",
                detail: "Halte das iPhone hochkant und aufrecht. So passt der AR-Pfad zu deiner Blickrichtung."
            )
            InfoCard(
                icon: "camera.viewfinder",
                title: "Leicht nach vorne neigen",
                detail: "Neige das Gerät etwas nach vorne, damit die Kamera den Weg und den Boden direkt vor dir erfasst."
            )
            InfoCard(
                icon: "arrow.triangle.2.circlepath",
                title: "Kurz kalibrieren",
                detail: "Schwenke beim Start langsam, bis sich die Umgebung eingemessen hat – dann liegt der Pfad stabil auf dem Boden."
            )

            Text("Das ist der letzte Schritt: Mit «Weiter» wird dein Profil gespeichert. Die Ausrichtung kannst du jederzeit ändern – die App misst sich neu ein, sobald du den AR-Modus startest.")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppMetrics.Space.xxl)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ScrollView {
        PhoneOrientationScreen()
            .padding(AppMetrics.Space.l)
    }
    .background(AppColor.backgroundPrimary)
}