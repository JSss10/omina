// IntroCarouselView.swift
// Omina
//
// Intro vor der Registrierung: drei Illustrations-Slides.
// Aufbau je Seite nach Entwurf – Akzentleiste und "Überspringen" oben, darunter
// Titel und Unterzeile, in der freien Mitte die Illustration, darunter der
// erklärende Absatz, dann die Seitenpunkte und die Hauptaktion am unteren Rand.
//
// Gewischt wird seitwärts, die Punkte zeigen, wo man steht; "Weiter" blättert
// vor und heisst auf der letzten Seite "Starte jetzt". "Überspringen" führt von
// jeder Seite aus direkt zur Registrierung – niemand muss sich durch das Intro
// arbeiten.
//
// Styling gemäss Styleguide v1.0 (AppColor, AppTypography, AppMetrics) und dem
// gemeinsamen Primär-Button.
//
// Die Illustrationen (IntroBarriers/IntroPlaces/IntroProfile) liegen im
// Asset-Katalog; fehlt eine, steht ein Platzhalter an ihrer Stelle
// (siehe AssetMedia.swift).

import SwiftUI

struct IntroCarouselView: View {
    @State private var page = 0
    @State private var showSignUp = false

    private let slides: [IntroSlide] = [
        IntroSlide(
            illustration: "IntroBarriers",
            placeholderSymbol: "figure.stairs",
            title: "Barrieren sehen",
            subtitle: "Stufen und Steigungen, bevor du da bist",
            body: "Die Karte zeigt, was auf deinem Weg liegt: Stufen, fehlende Absenkungen, enge Gassen und grobes Pflaster."
        ),
        IntroSlide(
            illustration: "IntroPlaces",
            placeholderSymbol: "storefront",
            title: "Passende Orte",
            subtitle: "Zugänglichkeit von Cafés, Läden und WCs",
            body: "Zu jedem Ort siehst du, ob Eingang, Türbreite und WC für dich reichen – aus den Daten von ginto und OpenStreetMap."
        ),
        IntroSlide(
            illustration: "IntroProfile",
            placeholderSymbol: "figure.roll",
            title: "Deine Route",
            subtitle: "Auf dein Profil zugeschnitten",
            body: "Rollstuhltyp, Masse und Fähigkeiten bestimmen, was für dich eine Barriere ist. Gewarnt wird nur, wo es nicht weitergeht."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()
            skipButton

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            pageIndicator
                .padding(.top, AppMetrics.Space.xl)

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

    private var isLastSlide: Bool {
        page >= slides.count - 1
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
    private var pageIndicator: some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
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

    /// Titel und Unterzeile stehen oben, die Illustration in der freien Mitte,
    /// der Absatz am unteren Rand. Wächst der Inhalt über die Seite hinaus
    /// (grosse Dynamic-Type-Stufen bis AX5), wird sie scrollbar statt
    /// abgeschnitten.
    private func slideView(_ slide: IntroSlide) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(for: slide)

                    Spacer(minLength: AppMetrics.Space.l)

                    AssetImage(
                        name: slide.illustration,
                        placeholderSymbol: slide.placeholderSymbol
                    )
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 300)

                    Spacer(minLength: AppMetrics.Space.l)

                    Text(slide.body)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
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
}

/// Ein Intro-Slide: Titel, Unterzeile, Illustration und ein erklärender Absatz
/// darunter.
private struct IntroSlide {
    /// Name der Illustration im Asset-Katalog.
    let illustration: String
    /// SF-Symbol, das den Platzhalter trägt, solange die Datei fehlt.
    let placeholderSymbol: String
    let title: String
    let subtitle: String
    let body: String
}

#Preview {
    NavigationStack {
        IntroCarouselView()
    }
}