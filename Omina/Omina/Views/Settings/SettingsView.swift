// SettingsView.swift
// Omina
//
// Profil-Tab. Zeigt Profil-Übersicht und den "Heute mit Begleitung"-Toggle,
// der direkt auf das gebundene UserProfile schreibt, dazu Einstellungen
// (Benachrichtigungen, Karte, Sprache, Datenschutz) und das Abmelden.

import SwiftUI
import Auth

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @Binding var profile: UserProfile

    // Daten-Präferenzen. Der WLAN-Toggle wird vom künftigen
    // Offline-Caching ausgewertet; der Cache-Key ist dort definiert.
    @AppStorage("omina.wifiOnlyUpdates") private var wifiOnlyUpdates = false
    @State private var showingCacheDeleteConfirm = false
    @State private var showingSignOutConfirm = false

    // Geteilte Karten-Präferenzen (auch über das Ebenen-Menü auf der
    // Karte änderbar).
    @StateObject private var mapPreferences = MapPreferences.shared
    @StateObject private var avatarStore = AvatarStore.shared

    var body: some View {
        NavigationStack {
            Form {
                // Die Group gibt die Zeilenfläche an jede Section weiter,
                // damit sie nicht an jeder einzeln steht.
                Group {
                    profileHeaderSection
                    profileSection
                    companionSection
                    editSection
                    notificationsSection
                    mapSection
                    generalSection
                    privacyAndAboutSection
                    accountSection
                }
                .appFormRowBackground()
            }
            // Platz für die schwebende Navigationsleiste: Das Formular steckt
            // in einem eigenen NavigationStack und übernimmt den Abstand von
            // aussen nicht – sonst läge «Abmelden» als letzte Zeile hinter der
            // Leiste.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: AppMetrics.tabBarInset)
            }
            .appFormBackground()
            .tint(AppColor.accentPrimary)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { avatarStore.loadIfNeeded() }
            .trackScreen("settings")
            .alert("Barrieren-Daten löschen?", isPresented: $showingCacheDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    deleteBarrierCache()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Gecachte Daten werden entfernt und beim nächsten Start neu geladen. Offline sind dann keine Barrieren verfügbar.")
            }
            .confirmationDialog(
                "Du kannst dich jederzeit wieder anmelden. Dein Profil bleibt gespeichert.",
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Abmelden", role: .destructive) {
                    Task { try? await authService.signOut() }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    // MARK: - Konto (Abmelden)

    private var accountSection: some View {
        Section {
            NavigationLink {
                NewPasswordView(showsNavigationBar: true)
            } label: {
                Label("Passwort ändern", systemImage: "key")
            }

            Button(role: .destructive) {
                showingSignOutConfirm = true
            } label: {
                Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Konto")
        }
    }

    // MARK: - Benachrichtigungen

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Benachrichtigungen", systemImage: "bell")
            }
        }
    }

    // MARK: - Karte

    private var mapSection: some View {
        Section("Karte") {
            Picker(selection: $mapPreferences.style) {
                ForEach(MapStyleChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } label: {
                Label("Kartenansicht", systemImage: "map")
            }

            Picker(selection: $mapPreferences.appearance) {
                ForEach(MapAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            } label: {
                Label("Kartendesign", systemImage: "circle.lefthalf.filled")
            }
        }
    }

    // MARK: - Allgemein (Sprache, Daten)

    private var generalSection: some View {
        Section("Allgemein") {
            NavigationLink {
                LanguageSettingsView()
            } label: {
                Label("Sprache", systemImage: "globe")
            }

            Toggle(isOn: $wifiOnlyUpdates) {
                Label("Nur über WLAN aktualisieren", systemImage: "wifi")
            }

            Button(role: .destructive) {
                showingCacheDeleteConfirm = true
            } label: {
                Label("Barrieren-Daten löschen", systemImage: "trash")
            }
        }
    }

    private func deleteBarrierCache() {
        // Cache-Key des kommenden Offline-Cachings; heute noch leer.
        UserDefaults.standard.removeObject(forKey: "omina.barrierCache")
    }

    // MARK: - Profil-Kopf (Avatar, Name, Rollstuhltyp)

    private var profileHeaderSection: some View {
        Section {
            NavigationLink {
                ProfileEditView(profile: $profile)
            } label: {
                HStack(spacing: AppMetrics.Space.m) {
                    avatar

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(profile.wheelchairType.displayName)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(.vertical, AppMetrics.Space.s)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(displayName), \(profile.wheelchairType.displayName), Profil bearbeiten")
            }
        }
    }

    /// Profilbild (in den Einstellungen erfasst), sonst Initialen-Monogramm.
    private var avatar: some View {
        ZStack {
            if let photo = avatarStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(AppColor.accentPrimary)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(AppColor.onAccent)
                } else {
                    Text(initials)
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColor.onAccent)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Voller Name aus den Auth-Metadaten; sonst freundlicher Fallback.
    private var displayName: String {
        let metadata = authService.currentUser?.userMetadata
        func string(_ key: String) -> String? {
            if case .string(let value)? = metadata?[key] {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
        let parts = [string("first_name"), string("last_name")].compactMap { $0 }
        return parts.isEmpty ? "Mein Profil" : parts.joined(separator: " ")
    }

    /// Initialen für das Avatar-Monogramm (z. B. "JS").
    private var initials: String {
        let metadata = authService.currentUser?.userMetadata
        var result = ""
        if case .string(let first)? = metadata?["first_name"],
           let c = first.trimmingCharacters(in: .whitespaces).first {
            result.append(c)
        }
        if case .string(let last)? = metadata?["last_name"],
           let c = last.trimmingCharacters(in: .whitespaces).first {
            result.append(c)
        }
        return result.uppercased()
    }

    // MARK: - Profil

    private var profileSection: some View {
        Section("Mein Profil") {
            row("Rollstuhltyp", profile.wheelchairType.displayName)
            row("Mobilitätskategorie", profile.mobilityCategory.displayName)
            row("Breite", "\(profile.widthCm) cm  (effektiv \(profile.effectiveWidthNeeded) cm)")
            row("Gesamthöhe (sitzend)", "\(profile.heightCm) cm")
            row("Sitzhöhe", "\(profile.seatHeightCm) cm")
            row("Länge", "\(profile.lengthCm) cm")
            row("Gewicht", "\(profile.weightKg) kg")
            row("Tempo", String(format: "%.1f km/h", profile.effectiveTravelSpeedKmh))
            row("Max. Steigung", "\(Int(profile.effectiveMaxIncline)) %")
            row("Max. Bordstein", "\(Int(profile.effectiveMaxCurb)) cm")
            row("Oberflächentoleranz", profile.surfaceTolerance.displayName)
        }
    }

    // MARK: - Heute (Tages-Zustände: Begleitung, Nässe, Energie)

    private var companionSection: some View {
        Section {
            Toggle("Heute mit Begleitperson", isOn: $profile.companionTodayOverride)
            Toggle("Nasse Bedingungen", isOn: $profile.wetConditionsToday)
            Toggle("Heute weniger Energie", isOn: $profile.lowEnergyToday)
        } header: {
            Text("Heute")
        } footer: {
            Text(todayFooter)
        }
    }

    private var todayFooter: String {
        var parts: [String] = []
        if profile.companionTodayOverride {
            parts.append("Begleitung: Limits erhöht (+\(Int(profile.companionInclineBonus)) % Steigung, +\(Int(profile.companionCurbBonus)) cm Bordstein).")
        }
        if profile.wetConditionsToday {
            parts.append("Nässe: Oberflächen-Toleranz eine Stufe strenger.")
        }
        if profile.lowEnergyToday {
            parts.append("Weniger Energie: Grund-Limits um 20 % gesenkt.")
        }
        if parts.isEmpty {
            return "Tages-Zustände passen deine Warn-Schwellen temporär an – dein Profil bleibt unverändert."
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Edit-Link + Gespeicherte Orte

    private var editSection: some View {
        Section {
            NavigationLink {
                ProfileEditView(profile: $profile)
            } label: {
                Label("Profil bearbeiten", systemImage: "pencil")
            }

            NavigationLink {
                SavedPlacesListView(profile: profile, showsNavigationBar: true)
            } label: {
                Label("Gespeicherte Orte", systemImage: "bookmark")
            }
        }
    }

    // MARK: - Datenschutz + About

    private var privacyAndAboutSection: some View {
        Section {
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Datenschutz", systemImage: "lock")
            }
            NavigationLink {
                AboutView()
            } label: {
                Label("Über die App", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}