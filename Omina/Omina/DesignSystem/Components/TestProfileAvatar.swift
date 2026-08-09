// TestProfileAvatar.swift
// Omina
//
// Avatar-Darstellung eines Feldtest-Profils. Liegt bei den Design-System-
// Komponenten, weil sie rein visuell ist – das Modell dazu steht in
// Models/TestProfile.swift.

import SwiftUI

/// Rundes Avatar-Bild eines Testprofils im App-Stil: gefüllter Kreis in einer
/// Violett-Stufe des Design-Systems + weisse Initialen, mit weichem Schatten
/// (wie die Avatare auf Home/Profil). Jedes Profil erhält eine eigene Stufe,
/// bleibt also markenkonform und trotzdem visuell unterscheidbar.
struct TestProfileAvatar: View {
    let profile: TestProfile
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .fill(profile.avatarColor)
            // Immer weiss: die Violett-Stufen sind in beiden Modi dunkel.
            Text(profile.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppColor.Violet.v950.opacity(0.18), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}
