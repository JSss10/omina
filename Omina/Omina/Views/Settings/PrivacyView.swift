// PrivacyView.swift
// Omina
//
// Datenschutz-Übersicht und lokales Konto-Löschen. Vollständige Server-Löschung
// (Auth-User in Supabase) erfordert Admin-Aktion und wird via Mail abgewickelt –
// das ist in der UI klar so dokumentiert.

import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        Form {
            collectedSection
            storageSection
            deleteSection
            supportSection
        }
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Konto und Daten löschen?", isPresented: $showingDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                performLocalDeletion()
            }
        } message: {
            Text("Dein Profil und deine Einstellungen werden lokal entfernt und du wirst abgemeldet. Server-seitige Daten (Account und gesendetes Feedback) bleiben bestehen, bis du die Löschung per Mail anforderst.")
        }
        .overlay {
            if isDeleting {
                ProgressView()
                    .controlSize(.large)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Sections

    private var collectedSection: some View {
        Section {
            row("Profil", "Rollstuhltyp, Maße, Limits, Begleitung")
            row("Standort", "Während Nutzung, nicht im Hintergrund")
            row("Kamera", "Nur in der AR-Ansicht, keine Aufnahmen")
            row("Feedback", "Deine Rückmeldungen zu Barrieren")
        } header: {
            Text("Welche Daten")
        } footer: {
            Text("Standort und Kamera werden ausschließlich für die App-Funktion benötigt; es findet keine Verhaltens-Analyse statt.")
        }
    }

    private var storageSection: some View {
        Section {
            row("Profil + Einstellungen", "Nur lokal (UserDefaults)")
            row("Account (E-Mail)", "Supabase, EU-Region")
            row("Feedback", "Supabase, EU-Region")
        } header: {
            Text("Wo gespeichert")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Konto und Daten löschen", systemImage: "trash")
            }
            .disabled(isDeleting)
        } footer: {
            Text("Lokale Daten werden sofort gelöscht. Vollständige Server-Löschung folgt nach manueller Anfrage.")
        }
    }

    private var supportSection: some View {
        Section {
            Link(destination: URL(string: "mailto:jessica.schneiter@bluewin.ch?subject=Omina%20–%20Konto%20löschen")!) {
                Label("Server-Löschung anfordern", systemImage: "envelope")
            }
        } footer: {
            Text("Schreib eine kurze Mail mit deiner registrierten Adresse; deine Server-Daten werden innerhalb von 14 Tagen entfernt.")
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func performLocalDeletion() {
        isDeleting = true
        ProfileService.shared.deleteLocalProfile()
        UserDefaults.standard.removeObject(forKey: "omina.notificationSettings")

        Task {
            try? await authService.signOut()
            isDeleting = false
        }
    }
}
