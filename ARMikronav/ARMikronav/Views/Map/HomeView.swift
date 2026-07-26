// HomeView.swift
// ARMikronav
//
// Haupt-Container für authentifizierte User. Hält das MapViewModel und stellt
// die Tab-Navigation bereit: Home (Homescreen), Karte, Kamera (AR), Orte
// und Profil. Karte und Kamera laufen im Vollbild – dort wird die Tab-Leiste
// ausgeblendet, die Navigation ist also nur auf Home, Orte und
// Profil sichtbar. Filter- und Barrieren-State bleiben beim Tab-Wechsel
// erhalten, weil Karte und AR auf dem gleichen ViewModel laufen. Das
// Profil-Binding fliesst von hier weiter ins Profil (Settings/Abmelden, S1).

import SwiftUI
import CoreLocation

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @Binding var profile: UserProfile

    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationService = LocationService.shared
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home, map, ar, saved, profile
    }

    init(profile: Binding<UserProfile>) {
        _profile = profile
        // Aktiver Tab ohne getönte Hintergrund-/Auswahlfläche: nur Icon und
        // Label wechseln auf die Akzentfarbe, keine Kapsel dahinter.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.selectionIndicatorTintColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        tabView
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

    // Fünf Tabs; Karte und Kamera blenden die Tab-Leiste aus (Vollbild), damit
    // die Navigation nur auf Home, Orte und Profil erscheint.
    private var tabView: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                onOpenMap: { selectedTab = .map }
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(Tab.home)

            mapContent
                .tabItem {
                    Label("Karte", systemImage: "map.fill")
                }
                .tag(Tab.map)

            arContent
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label("Kamera", systemImage: "arkit")
                }
                .tag(Tab.ar)

            NavigationStack {
                SavedPlacesListView()
            }
            .tabItem {
                Label("Orte", systemImage: "bookmark.fill")
            }
            .tag(Tab.saved)

            SettingsView(profile: $profile)
                .environmentObject(authService)
                .tabItem {
                    Label("Profil", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
    }

    private var mapContent: some View {
        // Die Tab-Leiste (Navbar) bleibt auf der Karte sichtbar – der frühere
        // Home-Button ist damit überflüssig und entfällt. Die Karte respektiert
        // unten die Safe Area, damit Bedienelemente über der Tab-Leiste liegen.
        MapView(profile: profile, viewModel: viewModel, onStartARRoute: startARRoute)
            // Der AR-FAB verschwindet während der aktiven Navigation: Das
            // Routen-Panel (Abbiege-Anweisung) darf die volle Breite nutzen.
            .overlay(alignment: .bottomTrailing) {
                if viewModel.activeRoute == nil {
                    arFAB
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: viewModel.activeRoute)
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

    /// "Route in AR starten" aus dem POI-Detail: Route berechnen,
    /// bei Erfolg in den AR-Tab wechseln.
    private func startARRoute(to poi: POI) {
        Task {
            if await viewModel.startNavigation(to: poi, profile: profile) {
                selectedTab = .ar
            }
        }
    }

    private var arFAB: some View {
        Button {
            selectedTab = .ar
        } label: {
            Image(systemName: "arkit")
                .font(.title)
                .foregroundStyle(.white)
                .padding(18)
                .background(Color.accentColor, in: Circle())
                .shadow(radius: 4)
        }
        // Gleicher Abstand nach unten wie die Karten-Buttons (MapView,
        // .padding(.bottom, 12)), damit AR-Button und Filter unten bündig sind.
        .padding(.trailing)
        .padding(.bottom, 12)
        .accessibilityLabel("In AR ansehen")
    }
}