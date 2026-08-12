// Screen11_MobilityCategory.swift
// Omina – Onboarding Schritt 2/8: Mobilitätskategorie wählen.
// Aufbau nach Entwurf: zweispaltiges Raster aus Illustration und Beschriftung.
// Die gewählte Kachel trägt oben rechts das Häkchen und eine violette
// Beschriftung – Auswahl also doppelt codiert, nicht allein über die Farbe.
//
// Alle Kategorien sind wählbar; bei nicht-Rollstuhl-Profilen erscheint der
// Dialog 1.1a ("in zukünftiger Version verfügbar"), die Auswahl wird aber
// gespeichert. Weiter geht es im Prototyp nur mit dem Rollstuhl-Profil.
//
// Die Illustrationen (Assets "Mobility…") folgen noch; bis dahin steht der
// Platzhalter mit dem jeweiligen Symbol an ihrer Stelle (AssetMedia.swift).
// Kacheln ohne Asset zeigen dauerhaft ein SF-Symbol – dort ist das die
// gestaltete Lösung und kein Platzhalter (siehe CategoryOption.asset).

import SwiftUI

struct Screen11_MobilityCategory: View {
    @Binding var draft: DraftProfile
    @State private var showingUnavailableDialog = false

    private let categories: [CategoryOption] = [
        CategoryOption(.wheelchair,        "Rollstuhlnutzende",      "MobilityWheelchair",        "figure.roll"),
        CategoryOption(.walkingDisability, "Gehbehinderung",         "MobilityWalkingDisability", "figure.walk.motion"),
        CategoryOption(.blind,             "Blindheit",              "MobilityBlind",             "eye.slash"),
        CategoryOption(.hearingImpairment, "Hörbehinderung",         "MobilityHearingImpairment", "ear.badge.waveform"),
        CategoryOption(.rollator,          "Rollator",               "MobilityWalker",          "figure.walk"),
        CategoryOption(.visualImpairment,  "Sehbehinderung",         "MobilityVisualImpairment",  "eye.trianglebadge.exclamationmark"),
        CategoryOption(.deaf,              "Gehörlosigkeit",         "MobilityDeaf",              "ear.trianglebadge.exclamationmark"),
        CategoryOption(.stroller,          "Kinderwagen / temporär", nil,                         "stroller"),
        CategoryOption(.elderly,           "Altersbedingt",          "MobilityElderly",           "figure.walk.arrival"),
        CategoryOption(.none,              "Ohne Einschränkung",     "MobilityNone",              "figure.walk")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: AppMetrics.Space.l, alignment: .top),
        GridItem(.flexible(), spacing: AppMetrics.Space.l, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: AppMetrics.Space.l) {
            LazyVGrid(columns: columns, spacing: AppMetrics.Space.l) {
                ForEach(categories) { option in
                    CategoryTile(
                        option: option,
                        selected: draft.mobilityCategory == option.category
                    ) {
                        draft.mobilityCategory = option.category
                        if option.category != .wheelchair {
                            showingUnavailableDialog = true
                        }
                    }
                }
            }

            Text("Im Prototyp ist aktuell nur die Rollstuhl-Kategorie vollständig umgesetzt.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppMetrics.Space.s)
        }
        .alert("Dieses Profil wird in einer zukünftigen Version verfügbar.", isPresented: $showingUnavailableDialog) {
            Button("Verstanden") {}
            Button("Rollstuhl-Profil wählen") {
                draft.mobilityCategory = .wheelchair
            }
        } message: {
            Text("Im Prototyp ist aktuell nur das Rollstuhl-Profil vollständig umgesetzt. Deine Auswahl wird gespeichert.")
        }
    }
}

// MARK: - Kachel

private struct CategoryOption: Identifiable {
    let category: MobilityCategory
    let label: String
    /// Name der Illustration im Asset-Katalog. `nil`, wenn die Kachel
    /// bewusst ein SF-Symbol statt einer Illustration zeigt.
    let asset: String?
    /// Bei Kacheln mit Illustration der Platzhalter, solange sie fehlt –
    /// bei Kacheln ohne Asset das dauerhaft gezeigte Symbol.
    let symbol: String

    init(_ category: MobilityCategory, _ label: String, _ asset: String?, _ symbol: String) {
        self.category = category
        self.label = label
        self.asset = asset
        self.symbol = symbol
    }

    var id: String { category.rawValue }
}

private struct CategoryTile: View {
    let option: CategoryOption
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppMetrics.Space.m) {
                ZStack(alignment: .topTrailing) {
                    tileMedia
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)

                    if selected {
                        SelectionMark(selected: true)
                            .offset(x: AppMetrics.Space.xs, y: -AppMetrics.Space.s)
                    }
                }

                Text(option.label)
                    .font(AppTypography.body)
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Illustration aus dem Katalog – oder, wo keine vorgesehen ist, das
    /// SF-Symbol. Es steht in der Leitfarbe, sobald die Kachel gewählt ist,
    /// und folgt damit derselben doppelten Codierung wie die Beschriftung.
    @ViewBuilder
    private var tileMedia: some View {
        if let asset = option.asset {
            AssetImage(name: asset, placeholderSymbol: option.symbol)
        } else {
            Image(systemName: option.symbol)
                .font(.system(size: 72, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textPrimary)
        }
    }
}