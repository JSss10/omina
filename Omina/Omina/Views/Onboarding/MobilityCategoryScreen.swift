// Screen11_MobilityCategory.swift
// Omina – Onboarding Schritt 2/7: Mobilitätskategorie wählen.
// Alle Kategorien sind wählbar; bei nicht-Rollstuhl-Profilen erscheint der
// Dialog 1.1a ("in zukünftiger Version verfügbar"), die Auswahl wird aber
// gespeichert. Weiter geht es im Prototyp nur mit dem Rollstuhl-Profil.

import SwiftUI

struct Screen11_MobilityCategory: View {
    @Binding var draft: DraftProfile
    @State private var showingUnavailableDialog = false

    private let categories: [(MobilityCategory, String, String)] = [
        (.wheelchair,         "Rollstuhlnutzende",          "figure.roll"),
        (.walkingDisability,  "Gehbehinderung",             "figure.walk.motion"),
        (.rollator,           "Rollator",                   "figure.walk"),
        (.visualImpairment,   "Sehbehinderung",             "eye.trianglebadge.exclamationmark"),
        (.blind,              "Blindheit",                  "eye.slash"),
        (.hearingImpairment,  "Hörbehinderung",             "ear.badge.waveform"),
        (.deaf,               "Gehörlosigkeit",             "ear.trianglebadge.exclamationmark"),
        (.stroller,           "Kinderwagen / temporär",     "figure.and.child.holdinghands"),
        (.elderly,            "Altersbedingt",              "figure.walk.arrival"),
        (.none,               "Ohne Einschränkung",         "figure.walk")
    ]

    var body: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            ForEach(categories, id: \.0) { category, label, icon in
                SelectionRow(
                    label: label,
                    icon: icon,
                    selected: draft.mobilityCategory == category
                ) {
                    draft.mobilityCategory = category
                    if category != .wheelchair {
                        showingUnavailableDialog = true
                    }
                }
            }

            Text("Im Prototyp ist aktuell nur die Rollstuhl-Kategorie vollständig umgesetzt.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
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