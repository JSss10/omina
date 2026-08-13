// LanguageSettingsView.swift
// Omina
//
// Sprachauswahl. Der Prototyp ist bewusst nur auf Deutsch
// verfügbar; EN/FR/IT sind sichtbar, aber deaktiviert.

import SwiftUI

struct LanguageSettingsView: View {
    private let languages: [(name: String, available: Bool)] = [
        ("Deutsch", true),
        ("English", false),
        ("Français", false),
        ("Italiano", false)
    ]

    var body: some View {
        Form {
            Section {
                ForEach(languages, id: \.name) { language in
                    HStack {
                        Text(language.name)
                            .foregroundStyle(language.available ? .primary : .secondary)
                        Spacer()
                        if language.available {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        language.available
                            ? "\(language.name), ausgewählt"
                            : "\(language.name), noch nicht verfügbar"
                    )
                }
            } footer: {
                Text("EN / FR / IT folgen in einer späteren Version")
            }
            .appFormRowBackground()
        }
        .appFormBackground()
        .navigationTitle("Sprache")
        .navigationBarTitleDisplayMode(.inline)
    }
}