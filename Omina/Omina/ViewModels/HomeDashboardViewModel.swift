// HomeDashboardViewModel.swift
// Omina
//
// Datenquelle des Homescreens: Wetter am aktuellen Standort (Open-Meteo,
// inkl. UV-Index), Name/Initialen aus den Auth-Metadaten und die neuesten
// Barrieren-Meldungen aus der ganzen Zürcher Altstadt. Die letzten Ziele kommen
// aus dem RecentDestinationsStore.

import Foundation
import Combine
import CoreLocation
import Auth

@MainActor
final class HomeDashboardViewModel: ObservableObject {

    // MARK: - Wetter
    @Published private(set) var weather: CurrentWeather?
    @Published private(set) var weatherPlaceName: String?
    @Published private(set) var isLoadingWeather = false
    @Published private(set) var weatherError: String?

    // MARK: - Neue Barrieren
    @Published private(set) var newBarriers: [Barrier] = []
    @Published private(set) var isLoadingBarriers = false
    @Published private(set) var barriersError: String?

    private let locationService = LocationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false
    private var hasLoadedWeatherForLocation = false

    /// Anzahl Barrieren-Meldungen auf dem Homescreen.
    private let maxBarrierEntries = 5
    /// Meldungen jünger als dieses Intervall gelten als "Neu" (7 Tage).
    static let newBadgeInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Begrüssung

    /// Vorname aus den Supabase-Auth-Metadaten (beim Sign-Up erfasst).
    var firstName: String? {
        guard let metadata = AuthService.shared.currentUser?.userMetadata,
              case .string(let first) = metadata["first_name"] else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Initialen für den Profil-Avatar (Vor- und Nachname, z. B. "JS").
    var initials: String {
        guard let metadata = AuthService.shared.currentUser?.userMetadata else { return "" }
        var result = ""
        if case .string(let first) = metadata["first_name"], let c = first.trimmingCharacters(in: .whitespaces).first {
            result.append(c)
        }
        if case .string(let last) = metadata["last_name"], let c = last.trimmingCharacters(in: .whitespaces).first {
            result.append(c)
        }
        return result.uppercased()
    }

    /// Tageszeitabhängige Anrede ohne Namen – im Entwurf steht sie in der
    /// ersten Zeile, der Vorname violett darunter.
    var salutation: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:  return "Guten Morgen"
        case 11..<18: return "Guten Tag"
        default:      return "Guten Abend"
        }
    }

    /// Tageszeitabhängige Begrüssung inkl. Vorname (VoiceOver, Ansagen).
    var greeting: String {
        if let firstName {
            return "\(salutation), \(firstName)!"
        }
        return "\(salutation)!"
    }

    // MARK: - Laden

    /// Startet Standort-Updates und lädt Wetter + Barrieren. Das Wetter wird
    /// nachgeladen, sobald der erste GPS-Fix eintrifft. Mehrfachaufrufe
    /// (onAppear bei jedem Tab-Wechsel) starten nicht neu.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        locationService.startUpdating()

        Task { await loadBarriers() }
        Task { await loadWeather() }

        // Erster GPS-Fix nach App-Start: Wetter für den echten Standort laden.
        locationService.$currentLocation
            .compactMap { $0 }
            .first()
            .sink { [weak self] _ in
                self?.handleFirstLocationFix()
            }
            .store(in: &cancellables)
    }

    private func handleFirstLocationFix() {
        guard !hasLoadedWeatherForLocation else { return }
        Task { await loadWeather() }
    }

    func refresh() async {
        async let weatherTask: Void = loadWeather()
        async let barriersTask: Void = loadBarriers()
        _ = await (weatherTask, barriersTask)
    }

    /// Wetter am aktuellen Standort (egal wo in der Schweiz, z. B. Luzern);
    /// ohne GPS-Fix Fallback auf das Testgebiet Kreis 1 (Zürich Altstadt).
    func loadWeather() async {
        isLoadingWeather = true
        weatherError = nil
        defer { isLoadingWeather = false }

        let coordinate: CLLocationCoordinate2D
        if let current = locationService.currentLocation?.coordinate {
            coordinate = current
            hasLoadedWeatherForLocation = true
        } else {
            coordinate = AppConfig.district1Center
        }

        do {
            async let weatherTask = WeatherService.shared.fetchCurrentWeather(for: coordinate)
            async let placeTask = WeatherService.shared.placeName(for: coordinate)
            weather = try await weatherTask
            weatherPlaceName = await placeTask
        } catch let error as WeatherServiceError {
            weatherError = error.userMessage
        } catch {
            // Netzwerk-/Transportfehler (kein HTTP-Status).
            weatherError = ErrorText.message(for: error, context: "Wetter konnte nicht geladen werden")
        }
    }

    /// Neueste aktive Barrieren-Meldungen – für die ganze Altstadt (der
    /// Radius um das Altstadt-Zentrum deckt Kreis 1 ab, sortiert nach Meldedatum).
    func loadBarriers() async {
        isLoadingBarriers = true
        barriersError = nil
        defer { isLoadingBarriers = false }

        do {
            let barriers = try await BarrierRepository.shared.fetchBarriers(
                near: AppConfig.oldTownCenter,
                radius: AppConfig.oldTownRadiusM
            )
            newBarriers = topBarriers(from: barriers)
        } catch {
            // Offline und noch nichts geladen: gebündelten Seed zeigen, statt
            // eine leere Liste mit Fehlermeldung.
            if newBarriers.isEmpty {
                let seed = topBarriers(from: SeedData.barriers)
                if seed.isEmpty {
                    barriersError = "Meldungen konnten nicht geladen werden."
                } else {
                    newBarriers = seed
                }
            }
        }
    }

    /// Die neuesten aktiven Barrieren (nach Meldedatum), begrenzt auf die
    /// Anzahl Homescreen-Einträge.
    private func topBarriers(from barriers: [Barrier]) -> [Barrier] {
        Array(
            barriers
                .filter { $0.isActive }
                .sorted { ($0.lastVerified ?? .distantPast) > ($1.lastVerified ?? .distantPast) }
                .prefix(maxBarrierEntries)
        )
    }

    /// Distanz vom aktuellen Standort zu einer Koordinate, nil ohne GPS-Fix.
    func distanceText(latitude: Double, longitude: Double) -> String? {
        guard let user = locationService.currentLocation else { return nil }
        let meters = user.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        return DistanceFormatter.awayString(fromMeters: meters)
    }

    /// Rohdistanz in Metern – Grundlage fürs Sortieren nach Nähe.
    func distance(latitude: Double, longitude: Double) -> Double? {
        guard let user = locationService.currentLocation else { return nil }
        return user.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}