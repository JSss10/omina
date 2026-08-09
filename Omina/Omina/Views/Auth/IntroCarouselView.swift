// IntroCarouselView.swift
// Omina
//
// Intro vor der Registrierung: drei Illustrations-Slides und ein Erklärvideo.
// Aufbau je Seite nach Entwurf – Akzentleiste und "Überspringen" oben, darunter
// Titel und Unterzeile, in der freien Mitte das Medium, darunter der erklärende
// Absatz, dann die Seitenpunkte und die Hauptaktion am unteren Rand.
//
// Gewischt wird seitwärts, die Punkte zeigen, wo man steht; "Weiter" blättert
// vor und heisst auf der letzten Seite "Starte jetzt". "Überspringen" führt von
// jeder Seite aus direkt zur Registrierung – niemand muss sich durch das Intro
// arbeiten.
//
// Die Video-Seite folgt dem Entwurf und weicht bewusst ab: Sie trägt keinen
// Absatz und keine Punkte, dafür füllt das Video die frei werdende Fläche.
//
// Styling gemäss Styleguide v1.0 (AppColor, AppTypography, AppMetrics) und dem
// gemeinsamen Primär-Button.
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
            title: "Barrieren sehen",
            subtitle: "Stufen und Steigungen, bevor du da bist",
            body: "Die Karte zeigt, was auf deinem Weg liegt: Stufen, fehlende Absenkungen, enge Gassen und grobes Pflaster."
        ),
        IntroSlide(
            media: .illustration(name: "IntroPlaces", symbol: "storefront"),
            title: "Passende Orte",
            subtitle: "Zugänglichkeit von Cafés, Läden und WCs",
            body: "Zu jedem Ort siehst du, ob Eingang, Türbreite und WC für dich reichen – aus den Daten von ginto und OpenStreetMap."
        ),
        IntroSlide(
            media: .illustration(name: "IntroProfile", symbol: "figure.roll"),
            title: "Deine Route",
            subtitle: "Auf dein Profil zugeschnitten",
            body: "Rollstuhltyp, Masse und Fähigkeiten bestimmen, was für dich eine Barriere ist. Gewarnt wird nur, wo es nicht weitergeht."
        ),
        IntroSlide(
            media: .video(resource: "IntroVideo"),
            title: "So funktioniert’s",
            subtitle: "Die App in zwei Minuten erklärt",
            body: nil
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            accentBar
            skipButton

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            if currentSlide.showsPageIndicator {
                pageIndicator
                    .padding(.top, AppMetrics.Space.xl)
            }

            primaryButton
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.xl)
                .padding(.bottom, AppMetrics.Space.s)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        // Der Entwurf zeigt keine Navigationsleiste: Die Akzentleiste sitzt
        // direkt unter der Statusleiste, weiter geht es über "Überspringen".
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView()
        }
    }

    // MARK: - Rahmen

    private var currentSlide: IntroSlide {
        slides[min(max(page, 0), slides.count - 1)]
    }

    private var isLastSlide: Bool {
        page >= slides.count - 1
    }

    /// Akzentleiste unter der Statusleiste (Entwurf): dekorative Markenlinie,
    /// kein Fortschritt – deshalb durchgehend gefüllt.
    private var accentBar: some View {
        Capsule()
            .fill(AppColor.Violet.v500)
            .frame(height: 4)
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.top, AppMetrics.Space.s + AppMetrics.Space.xs)
            .accessibilityHidden(true)
    }

    private var skipButton: some View {
        HStack {
            Spacer()
            Button {
                showSignUp = true
            } label: {
                Text("Überspringen")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textBrand)
                    .frame(minHeight: AppMetrics.Touch.minimum)
                    .padding(.horizontal, AppMetrics.Space.l)
                    .contentShape(Rectangle())
            }
        }
    }

    /// Punkte zeigen, auf welcher Seite man steht – gewischt wird seitwärts.
    /// Die Video-Seite steht ohne Punkte (Entwurf) und bleibt deshalb aussen vor.
    private var pageIndicator: some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            ForEach(indicatorPages, id: \.self) { index in
                Circle()
                    .fill(AppColor.accentPrimary.opacity(index == page ? 1 : 0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Seite \(page + 1) von \(slides.count)")
    }

    private var indicatorPages: [Int] {
        slides.indices.filter { slides[$0].showsPageIndicator }
    }

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

    // MARK: - Slide

    /// Titel und Unterzeile stehen oben, das Medium in der freien Mitte, der
    /// Absatz am unteren Rand. Wächst der Inhalt über die Seite hinaus (grosse
    /// Dynamic-Type-Stufen bis AX5), wird sie scrollbar statt abgeschnitten.
    private func slideView(_ slide: IntroSlide) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(for: slide)

                    if slide.mediaFillsFreeSpace {
                        media(for: slide)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, AppMetrics.Space.l)
                    } else {
                        Spacer(minLength: AppMetrics.Space.l)

                        media(for: slide)
                            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 300)

                        Spacer(minLength: AppMetrics.Space.l)

                        if let text = slide.body {
                            Text(text)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, AppMetrics.Space.l)
                .frame(
                    maxWidth: .infinity,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func header(for slide: IntroSlide) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text(slide.title)
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Text(slide.subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, AppMetrics.Space.m)
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

    private var isVideo: Bool {
        if case .video = media { return true }
        return false
    }

    /// Das Video füllt laut Entwurf die Fläche bis zum Button.
    var mediaFillsFreeSpace: Bool { isVideo }

    /// Die Video-Seite steht im Entwurf ohne Seitenpunkte.
    var showsPageIndicator: Bool { !isVideo }
}

#Preview {
    NavigationStack {
        IntroCarouselView()
    }
}