// SearchChrome.swift
// Omina
//
// Suchleiste, Filter-Schaltfläche und Kategorie-Chips – die Bedienzeile, die
// im Entwurf sowohl auf dem Homescreen als auch auf der Karte und im
// Such-Sheet steht. Damit sehen alle drei Orte gleich aus und verhalten sich
// gleich.

import SwiftUI

// MARK: - Suchfeld

/// Suchleiste als getönte Kapsel. `isButton` macht daraus eine reine
/// Schaltfläche (Karte, Homescreen), sonst steht ein echtes Eingabefeld darin.
struct SearchBar: View {
    let placeholder: String
    var text: Binding<String>?
    var isFocused: FocusState<Bool>.Binding?
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    /// Fläche der Kapsel – auf der Karte weiss, sonst violett getönt.
    var background: Color = AppColor.surfaceTinted

    var body: some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(AppColor.textBrand)

            if let text {
                field(text)
            } else {
                Text(placeholder)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppMetrics.Space.m + AppMetrics.Space.xs)
        .frame(height: AppMetrics.Touch.primary)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func field(_ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(AppTypography.body)
            .foregroundStyle(AppColor.textPrimary)
            .tint(AppColor.accentPrimary)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .modifier(OptionalFocus(isFocused: isFocused))
            .onSubmit { onSubmit?() }

        if !text.wrappedValue.isEmpty {
            Button {
                onClear?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColor.textSecondary)
            }
            .accessibilityLabel("Suche löschen")
        }
    }
}

/// Hängt den Fokus nur an, wenn einer übergeben wurde.
private struct OptionalFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let isFocused {
            content.focused(isFocused)
        } else {
            content
        }
    }
}

// MARK: - Filter-Schaltfläche

/// Filter-Schaltfläche neben der Suche. Die Zahl der gesetzten Filter steht
/// als Plakette oben rechts – so sieht man, dass die Karte gerade nicht alles
/// zeigt, ohne das Sheet zu öffnen.
struct FilterIconButton: View {
    let activeCount: Int
    var background: Color = AppColor.surfaceTinted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(AppColor.textBrand)
                .frame(width: AppMetrics.Touch.primary, height: AppMetrics.Touch.primary)
                .background(background, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.onAccent)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 3)
                            .background(AppColor.accentPrimary, in: Capsule())
                    }
                }
        }
        .accessibilityLabel(
            activeCount > 0 ? "Filter, \(activeCount) aktiv" : "Filter"
        )
    }
}

// MARK: - Kategorie-Chips

/// Kategorie als Kapsel mit Symbol und Text (Homescreen). Der aktive Chip ist
/// violett gefüllt, die übrigen bleiben getönt.
struct CategoryPill: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppMetrics.Space.s) {
                // Gewählter Chip: gefülltes Symbol – die Auswahl steckt so
                // nicht allein in der Farbe.
                Image(systemName: AppSymbol.name(symbol, isSelected: isSelected))
                    .font(.system(size: 17, weight: .regular))
                Text(label)
                    .font(AppTypography.body)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textBrand)
            .padding(.horizontal, AppMetrics.Space.m + AppMetrics.Space.xs)
            .frame(height: AppMetrics.Touch.minimum)
            .background(
                isSelected ? AnyShapeStyle(AppColor.accentPrimary) : AnyShapeStyle(AppColor.surfaceTinted),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack(spacing: AppMetrics.Space.m) {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            SearchBar(placeholder: "Suchst du nach etwas Bestimmten?")
            FilterIconButton(activeCount: 2) {}
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                CategoryPill(label: "Restaurant", symbol: "fork.knife", isSelected: true) {}
                CategoryPill(label: "Café", symbol: "cup.and.saucer.fill", isSelected: false) {}
                CategoryPill(label: "WC", symbol: "toilet.fill", isSelected: false) {}
            }
        }
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}