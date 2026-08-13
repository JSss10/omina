// SplashView.swift
// Omina
//
// Screen 0.1 – Startbild, solange der Auth-Check bzw. das Laden des Profils
// läuft. Das Logo-Lockup (Signet · Wortmarke · Claim) steht waagrecht zentriert
// knapp oberhalb der Bildschirmmitte, darunter schliesst die Stadt-Illustration
// bündig am unteren Rand ab.
//
// Der getönte Grund (BackgroundMuted, wie bei den Zustands-Screens) läuft über
// den ganzen Bildschirm – auch hinter der Statusleiste, damit dort kein weisser
// Streifen stehen bleibt.
//
// Logo (Asset "LogoMark") und Illustration (Asset "SplashCity") folgen noch –
// bis dahin stehen ein getönter Kreis und eine leere Fläche an ihrer Stelle
// (siehe AssetMedia.swift).

import SwiftUI

struct SplashView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Wortmarke und Claim gehören zum Logo und nicht zur UI-Schriftskala: Sie
    // stehen grösser als "largeTitle" (34 pt), wachsen über @ScaledMetric aber
    // trotzdem mit Dynamic Type mit.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title3) private var claimSize: CGFloat = 20
    /// Kantenlänge des Signets bzw. seines Platzhalter-Kreises.
    @ScaledMetric(relativeTo: .largeTitle) private var signetSize: CGFloat = 84

    /// Der Entwurf setzt das Lockup nicht in die exakte Mitte, sondern knapp
    /// 50 pt darüber – so bleibt es frei von der Skyline am unteren Rand.
    private let opticalLift: CGFloat = 48

    var body: some View {
        ZStack(alignment: .bottom) {
            // Die getönte Fläche liegt ganz zuunterst und deckt den ganzen
            // Bildschirm ab – auch hinter der Statusleiste und dem
            // Home-Indikator. Sonst bliebe oben ein weisser Streifen stehen.
            AppColor.backgroundMuted
                .ignoresSafeArea()

            // Stadt-Illustration bündig am unteren Rand, über die ganze Breite.
            AssetImage(name: "SplashCity", placeholderSymbol: "building.2", contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .ignoresSafeArea(edges: .bottom)

            logoLockup
                .padding(.horizontal, AppMetrics.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, opticalLift * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundMuted.ignoresSafeArea())
        // Im Entwurf steht kein Ladeindikator; dass die App noch lädt, sagt
        // VoiceOver zusammen mit der Marke an.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Omina – know what’s ahead. App wird geladen.")
    }

    // MARK: - Lockup

    /// Signet links, Wortmarke und Claim rechts daneben. Ab den
    /// Accessibility-Textgrössen stapelt sich beides, sonst würde die Zeile
    /// über den Bildschirmrand hinauslaufen.
    @ViewBuilder
    private var logoLockup: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
                signet
                wordmark
            }
        } else {
            HStack(spacing: AppMetrics.Space.l) {
                signet
                wordmark
            }
        }
    }

    /// App-Logo; bis es vorliegt, der getönte Kreis aus dem Entwurf.
    private var signet: some View {
        Group {
            if UIImage(named: "LogoMark") != nil {
                Image("LogoMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Der Grund ist selbst getönt – der Platzhalter steht deshalb
                // eine Stufe kräftiger, sonst verschwände er darin.
                Circle()
                    .fill(AppColor.accentMuted)
            }
        }
        .frame(width: signetSize, height: signetSize)
    }

    /// Wortmarke in Kleinbuchstaben (Marke), darunter der Claim.
    private var wordmark: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
            Text("Omina")
                .font(.system(size: wordmarkSize, weight: .bold))
                .foregroundStyle(AppColor.textBrand)

            Text("know what’s ahead")
                .font(.system(size: claimSize, weight: .regular))
                .foregroundStyle(AppColor.textBrand)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SplashView()
}