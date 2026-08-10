// SheetChrome.swift
// Omina
//
// Gemeinsame Bausteine der Karten-Sheets (Figma: Filter, Karteneinstellungen,
// Routen, Suche). Alle vier tragen dieselbe Kopfzeile, dieselben violetten
// Abschnittstitel und dieselben getönten Karten – hier liegen sie einmal,
// damit die Sheets nicht auseinanderlaufen.

import SwiftUI

// MARK: - Kopfzeile

/// Kopfzeile der Sheets: Schliessen links, Titel mittig, Bestätigen rechts.
/// Beide Aktionen sind runde, getönte Icon-Buttons mit 44 pt Trefferfläche.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void
    /// Häkchen rechts. Ohne Aktion bleibt der Platz frei, damit der Titel
    /// trotzdem mittig sitzt.
    var onConfirm: (() -> Void)?

    var body: some View {
        HStack(spacing: AppMetrics.Space.s) {
            SheetCircleButton(symbol: "xmark", label: "Schliessen", action: onClose)

            Spacer(minLength: 0)

            Text(title)
                .font(AppTypography.title3)
                .foregroundColor(AppColor.textBrand)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let onConfirm {
                SheetCircleButton(symbol: "checkmark", label: "Fertig", action: onConfirm)
            } else {
                // Platzhalter in Buttongrösse: hält den Titel in der Mitte.
                Color.clear.frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
    }
}

/// Runder Icon-Button der Sheet-Kopfzeile.
struct SheetCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppColor.accentPrimary)
                .frame(width: AppMetrics.Touch.minimum, height: AppMetrics.Touch.minimum)
                .background(AppColor.surfaceTinted, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Abschnitt mit getönter Karte

/// Abschnitt eines Sheets: violetter Titel, darunter die getönte Karte mit
/// den Zeilen und – wo nötig – ein erklärender Hinweis.
struct SheetSection<Content: View>: View {
    let title: String
    let footnote: String?
    let content: Content

    init(
        title: String,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content
            }
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )

            if let footnote {
                Text(footnote)
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Zeilen innerhalb der Karte

/// Rundes, getöntes Symbolfeld am Zeilenanfang.
struct SheetRowIcon: View {
    let symbol: String
    var isEnabled: Bool = true
    /// Volle Akzentfläche mit hellem Symbol (Entwurf: Start und Ziel im
    /// Routen-Sheet); sonst der helle Kreis mit violettem Symbol.
    var isFilled: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isFilled ? AppColor.accentPrimary : AppColor.accentMuted)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(isFilled ? AppColor.onAccent : AppColor.accentPrimary)
        }
        .frame(width: 40, height: 40)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

/// Trennlinie zwischen zwei Zeilen – eingerückt bis zur Textkante, damit die
/// Symbolspalte durchläuft.
private struct SheetRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColor.borderDecorative)
            .frame(height: 1)
            .padding(.leading, 40 + AppMetrics.Space.m + AppMetrics.Space.m)
    }
}

/// Zeile mit Schalter (Filter-Sheet).
struct SheetToggleRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                HStack(spacing: AppMetrics.Space.m) {
                    SheetRowIcon(symbol: symbol)
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColor.textPrimary)
                }
            }
            .tint(AppColor.accentPrimary)
            .padding(.horizontal, AppMetrics.Space.m)
            .padding(.vertical, 10)
            .frame(minHeight: AppMetrics.Touch.minimum)

            if showsDivider {
                SheetRowDivider()
            }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Segment-Umschalter

/// Umschalter mit gleich breiten Segmenten; das aktive Segment ist violett
/// gefüllt. Deaktivierte Segmente bleiben sichtbar – sie zeigen an, was
/// später dazukommt, ohne dass man sie wählen kann.
struct SegmentedBar<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        /// Beschriftung (Textsegment) bzw. VoiceOver-Name (Symbolsegment).
        let label: String
        /// SF-Symbol; nil zeigt die Beschriftung als Text.
        var symbol: String?
        var isEnabled: Bool = true

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(4)
        .background(AppColor.surfaceTinted, in: Capsule())
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        return Button {
            selection = segment.value
        } label: {
            Group {
                if let symbol = segment.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text(segment.label)
                        .font(AppTypography.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundColor(isSelected ? AppColor.onAccent : AppColor.accentPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isSelected ? AnyShapeStyle(AppColor.accentPrimary) : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!segment.isEnabled)
        .opacity(segment.isEnabled ? 1 : 0.35)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(segment.isEnabled ? "" : "Noch nicht verfügbar")
    }
}