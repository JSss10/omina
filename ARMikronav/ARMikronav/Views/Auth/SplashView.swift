// SplashView.swift
// ARMikronav
//
// Screen 0.1 – Startbild, solange der Auth-Check bzw. das Laden des Profils
// läuft. Logo und App-Name sitzen in der unteren Bildschirmhälfte, darunter
// die Stadt-Illustration am unteren Rand.
//
// Logo (Asset "LogoMark") und Illustration (Asset "SplashCity") folgen noch –
// bis dahin stehen ein getönter Kreis und eine leere Fläche an ihrer Stelle
// (siehe AssetMedia.swift).

import SwiftUI

struct SplashView: View {
    /// Kantenlänge des Logos bzw. seines Platzhalter-Kreises.
    private let logoSize: CGFloat = 90

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.backgroundPrimary
                .ignoresSafeArea()

            // Stadt-Illustration bündig am unteren Rand, über die ganze Breite.
            AssetImage(name: "SplashCity", placeholderSymbol: "building.2", contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: AppMetrics.Space.xl) {
                Spacer()

                HStack(spacing: AppMetrics.Space.l) {
                    logo
                    Text("AR-Mikronavigation")
                        .font(AppTypography.title1)
                        .foregroundColor(AppColor.textBrand)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AR-Mikronavigation")

                // Der Splash steht auch, während das Profil vom Server kommt –
                // ohne Indikator sähe das nach eingefrorener App aus.
                ProgressView()
                    .tint(AppColor.accentPrimary)
                    .accessibilityLabel("App wird geladen")

                Spacer()
            }
        }
    }

    /// App-Logo; bis es vorliegt, der getönte Kreis aus dem Entwurf.
    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "LogoMark") != nil {
            Image("LogoMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: logoSize, height: logoSize)
        } else {
            Circle()
                .fill(AppColor.backgroundMuted)
                .frame(width: logoSize, height: logoSize)
        }
    }
}

#Preview {
    SplashView()
}