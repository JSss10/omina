// IntroCarouselView.swift
// ARMikronav
//
// Intro vor der Registrierung: drei Illustrations-Slides und ein
// Erklärvideo. "Weiter" blättert vor (wischen geht ebenso, die Punkte
// zeigen, wo man steht), auf dem letzten Slide steht dort "Starte jetzt".
// "Überspringen" führt von jeder Seite aus direkt zur Registrierung –
// niemand muss sich durch das Intro arbeiten.
//
// Styling gemäss Styleguide v1.0 (AppColor, AppTypography, AppMetrics) und
// dem gemeinsamen Primär-Button. Titel und Texte stehen linksbündig, die
// Aktion sitzt fix am unteren Rand.
//
// Die Illustrationen (IntroBarriers/IntroPlaces/IntroProfile) und das Video
// (IntroVideo.mp4) kommen noch dazu; bis dahin stehen Platzhalter an ihrer
// Stelle (siehe AssetMedia.swift).

import SwiftUI

struct IntroCarouselView: View {
    @State private var page = 0
    @State private var showSignUp = false

    private let slides: [IntroSlide] = [
        IntroSlide(
            media: .illustration(name: "IntroBarriers", symbol: "figure.stairs"),
            title: "Barrieren sehen, bevor du dort bist",
            subtitle: "Stufen, Steigungen und Engstellen auf einen Blick",
            body: "Die Karte zeigt dir, was auf deinem Weg liegt – Stufen, fehlende Bordstein-Absenkungen, enge Gassen und grobes Pflaster. So entscheidest du vorher, nicht erst davor."
        ),
        IntroSlide(
            media: .illustration(name: "IntroPlaces", symbol: "storefront"),
            title: "Orte, die zu dir passen",
            subtitle: "Zugänglichkeit von Cafés, Restaurants und WCs",
            body: "Zu jedem Ort in der Altstadt siehst du, ob er für dich zugänglich ist – Eingang, Türbreite und WC, soweit die Daten von ginto und OpenStreetMap es hergeben."
        ),
        IntroSlide(
            media: .illustration(name: "IntroProfile", symbol: "figure.roll"),
            title: "Deine Grenzen, deine Route",
            subtitle: "Persönlich statt pauschal",
            body: "Dein Rollstuhltyp, deine Masse und deine Fähigkeiten bestimmen, was überhaupt eine Barriere ist. Die App warnt nur dort, wo es für dich wirklich nicht weitergeht."
        ),
        IntroSlide(
            media: .video(resource: "IntroVideo"),
            title: "So funktioniert die App",
            subtitle: "In zwei Minuten erklärt",
            body: nil
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            accentBar
            skipBar

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            pageIndicator
                .padding(.bottom, AppMetrics.Space.l)

            primaryButton
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.xxl)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView()
        }
    }

    // MARK: - Rahmen

    /// Hauptaktion: blättert bis zum letzten Slide weiter, dort geht es in die
    /// Registrierung. Wer das Intro überspringen will, nimmt "Überspringen".
    private var primaryButton: some View {
        Button(isLastSlide ? "Starte jetzt" : "Weiter") {
            if isLastSlide {
                showSignUp = true
            } else {
                withAnimation { page += 1 }
            }
        }
        .buttonStyle(.appPrimary)
    }

    private var isLastSlide: Bool {
        page >= slides.count - 1
    }

    /// Durchgehende Akzentlinie unter der Statusleiste (Entwurf).
    private var accentBar: some View {
        Rectangle()
            .fill(AppColor.accentPrimary)
            .frame(height: 3)
            .accessibilityHidden(true)
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Überspringen") { showSignUp = true }
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textBrand)
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.vertical, AppMetrics.Space.m)
        }
    }

    /// Punkte zeigen, auf welcher Seite man steht – gewischt wird seitwärts.
    private var pageIndicator: some View {
        HStack(spacing: AppMetrics.Space.s) {
            ForEach(slides.indices, id: \.self) { index in
                Circle()
                    .fill(AppColor.accentPrimary.opacity(index == page ? 1 : 0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Seite \(page + 1) von \(slides.count)")
    }

    // MARK: - Slide

    /// Wächst der Inhalt über die Seite hinaus (grosse Dynamic-Type-Stufen bis
    /// AX5), wird er scrollbar statt abgeschnitten.
    private func slideView(_ slide: IntroSlide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
                    Text(slide.title)
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColor.textBrand)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(slide.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                media(for: slide)
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 340)

                if let text = slide.body {
                    Text(text)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.bottom, AppMetrics.Space.m)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func media(for slide: IntroSlide) -> some View {
        switch slide.media {
        case let .illustration(name, symbol):
            AssetImage(name: name, placeholderSymbol: symbol)
                .accessibilityHidden(true)
        case let .video(resource):
            AssetVideo(resource: resource)
        }
    }
}

/// Ein Intro-Slide: Titel, Unterzeile, Medium und – ausser beim Video – ein
/// erklärender Absatz darunter.
private struct IntroSlide {
    enum Media {
        /// Illustration aus dem Asset-Katalog; `symbol` trägt den Platzhalter,
        /// bis die Datei vorliegt.
        case illustration(name: String, symbol: String)
        /// Erklärvideo als Bundle-Ressource (ohne Dateiendung).
        case video(resource: String)
    }

    let media: Media
    let title: String
    let subtitle: String
    let body: String?
}

#Preview {
    NavigationStack {
        IntroCarouselView()
    }
}