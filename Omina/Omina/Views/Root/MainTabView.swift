// MainTabView.swift
// Omina
//
// Haupt-Container für authentifizierte User. Hält das MapViewModel und stellt
// die Navigation bereit: Home (Homescreen), Karte, Kamera (AR), Orte und
// Profil. Statt der System-Tab-Leiste liegt die schwebende Kapsel aus dem
// Entwurf über dem Inhalt (OminaTabBar); Karte und Kamera laufen im Vollbild
// und zeigen sie nicht.
//
// Filter- und Barrieren-State bleiben beim Tab-Wechsel erhalten, weil Karte
// und AR auf dem gleichen ViewModel laufen. Das Profil-Binding fliesst von
// hier weiter ins Profil (Settings/Abmelden, S1).

import SwiftUI
import CoreLocation

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @Binding var profile: UserProfile

    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationService = LocationService.shared
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home, map, ar, saved, profile
    }

    /// Höhe, die die schwebende Leiste im Inhalt freihält.
    private let tabBarInset: CGFloat = 76

    private let tabItems: [OminaTabBar<Tab>.Item] = [
        .init(tab: .home, symbol: "house", label: "Start"),
        .init(tab: .map, symbol: "map", label: "Karte"),
        .init(tab: .ar, symbol: "camera.viewfinder", label: "Kamera"),
        .init(tab: .saved, symbol: "bookmark", label: "Orte"),
        .init(tab: .profile, symbol: "person", label: "Profil")
    ]

    init(profile: Binding<UserProfile>) {
        _profile = profile
    }

    /// Karte und AR laufen im Vollbild – dort steht die Leiste nicht im Weg.
    private var showsTabBar: Bool {
        selectedTab != .map && selectedTab != .ar
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tabView

            if showsTabBar {
                OminaTabBar(items: tabItems, selection: $selectedTab)
                    .padding(.horizontal, AppMetrics.Space.l)
                    .padding(.bottom, AppMetrics.Space.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsTabBar)
        // Standort-Berechtigung nur noch über Apples System-Prompt: beim
        // ersten Betreten fragen (notDetermined), danach kein eigener
        // Erklärungs-Screen mehr. Die Erklärung erfolgt einmalig im
        // Consent-Screen des Onboardings.
        .task {
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestAuthorization()
            }
        }
    }

    /// Fünf Tabs ohne System-Leiste – die Auswahl läuft über OminaTabBar.
    private var tabView: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                onOpenMap: { selectedTab = .map },
                onSelectCategory: openMap(with:),
                activeFilterCount: viewModel.activeFilterCount
            )
            .safeAreaInset(edge: .bottom) { tabBarSpacer }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.home)

            mapContent
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.map)

            arContent
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.ar)

            NavigationStack {
                SavedPlacesListView(profile: profile)
            }
            .safeAreaInset(edge: .bottom) { tabBarSpacer }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.saved)

            SettingsView(profile: $profile)
                .environmentObject(authService)
                .safeAreaInset(edge: .bottom) { tabBarSpacer }
                .toolbar(.hidden, for: .tabBar)
                .tag(Tab.profile)
        }
    }

    /// Hält am unteren Rand Platz frei, damit die schwebende Leiste keine
    /// Inhalte verdeckt.
    private var tabBarSpacer: some View {
        Color.clear.frame(height: tabBarInset)
    }

    private var mapContent: some View {
        // Die Karte läuft im Vollbild; Bedienelemente sitzen als Overlay darauf.
        // Der AR-Modus ist über den "Kamera"-Eintrag erreichbar.
        MapView(profile: profile, viewModel: viewModel, onStartARRoute: startARRoute)
    }

    // AR erst aufbauen, wenn der Tab aktiv ist – so starten Kamera und
    // AR-Session (samt zugehöriger Services) nicht im Hintergrund.
    @ViewBuilder
    private var arContent: some View {
        if selectedTab == .ar {
            ARModeView(
                profile: profile,
                viewModel: viewModel,
                originCoordinate: locationService.currentLocation?.coordinate,
                onClose: { selectedTab = .map }
            )
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    /// Kategorie-Chip vom Homescreen: Karte öffnen und die Suche mit dieser
    /// Kategorie vorbelegen.
    private func openMap(with category: String) {
        viewModel.pendingCategory = category
        selectedTab = .map
    }

    /// "Route in AR starten" aus dem POI-Detail: Route berechnen,
    /// bei Erfolg in den AR-Tab wechseln.
    private func startARRoute(to poi: POI) {
        Task {
            if await viewModel.startNavigation(to: poi, profile: profile) {
                selectedTab = .ar
            }
        }
    }
}