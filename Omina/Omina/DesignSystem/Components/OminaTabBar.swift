// OminaTabBar.swift
// Omina
//
// Schwebende Navigationsleiste aus dem Entwurf: eine violette Kapsel, die
// über dem Inhalt liegt. Der aktive Eintrag sitzt in einem weissen Kreis,
// zwischen den übrigen stehen feine Trennlinien.
//
// Sie ersetzt die System-Tab-Leiste nur optisch – die Auswahl läuft weiter
// über dieselbe Bindung wie zuvor (MainTabView).

import SwiftUI

struct OminaTabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let symbol: String
        /// Name für VoiceOver.
        let label: String

        var id: Tab { tab }
    }

    let items: [Item]
    @Binding var selection: Tab

    /// Kantenlänge des weissen Kreises hinter dem aktiven Eintrag.
    private let selectionSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppColor.onAccent.opacity(0.35))
                        .frame(width: 1, height: 24)
                        .accessibilityHidden(true)
                }

                button(for: item)
            }
        }
        .padding(.horizontal, AppMetrics.Space.s)
        .padding(.vertical, AppMetrics.Space.s)
        .background(AppColor.accentPrimary, in: Capsule())
        .shadow(color: AppColor.textBrand.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func button(for item: Item) -> some View {
        let isSelected = item.tab == selection
        return Button {
            selection = item.tab
        } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.onAccent)
                .frame(width: selectionSize, height: selectionSize)
                .background {
                    if isSelected {
                        Circle().fill(AppColor.onAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: AppMetrics.Touch.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private enum PreviewTab: Hashable {
    case home, map, ar, saved, profile
}

#Preview {
    @Previewable @State var selection = PreviewTab.home

    VStack {
        Spacer()
        OminaTabBar(
            items: [
                .init(tab: .home, symbol: "house", label: "Start"),
                .init(tab: .map, symbol: "map", label: "Karte"),
                .init(tab: .ar, symbol: "camera.viewfinder", label: "Kamera"),
                .init(tab: .saved, symbol: "bookmark", label: "Orte"),
                .init(tab: .profile, symbol: "person", label: "Profil")
            ],
            selection: $selection
        )
        .padding(.horizontal, AppMetrics.Space.l)
    }
    .background(AppColor.backgroundPrimary)
}