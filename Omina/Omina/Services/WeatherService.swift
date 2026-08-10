// WeatherService.swift
// Omina
//
// Lädt das aktuelle Wetter für den Standort des Users über die Open-Meteo-API
// (kostenlos, kein API-Key nötig). Neben Temperatur/Wind kommen gefühlte
// Temperatur und Luftfeuchtigkeit aus `current`, der UV-Index aus `hourly`
// (Open-Meteo führt UV nur stündlich – wir nehmen den Wert der aktuellen
// Stunde). Zusätzlich Reverse-Geocoding via CLGeocoder für den Ortsnamen.

import Foundation
import CoreLocation

/// Aktuelles Wetter an einer Koordinate (Ausschnitt der Open-Meteo-Antwort).
struct CurrentWeather: Equatable {
    let temperatureC: Double
    let feelsLikeC: Double
    let humidityPercent: Int
    let uvIndex: Double
    let windSpeedKmh: Double
    /// WMO-Wettercode (Open-Meteo).
    let weatherCode: Int
    let isDay: Bool

    /// SF-Symbol passend zum WMO-Wettercode.
    var symbolName: String {
        switch weatherCode {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// Deutsche Kurzbeschreibung des WMO-Wettercodes.
    var conditionDescription: String {
        switch weatherCode {
        case 0: return "Klar"
        case 1: return "Überwiegend klar"
        case 2: return "Teilweise bewölkt"
        case 3: return "Bedeckt"
        case 45, 48: return "Nebel"
        case 51, 53, 55: return "Nieselregen"
        case 56, 57: return "Gefrierender Nieselregen"
        case 61, 63, 65: return "Regen"
        case 66, 67: return "Gefrierender Regen"
        case 71, 73, 75: return "Schneefall"
        case 77: return "Schneegriesel"
        case 80, 81, 82: return "Regenschauer"
        case 85, 86: return "Schneeschauer"
        case 95: return "Gewitter"
        case 96, 99: return "Gewitter mit Hagel"
        default: return "Wechselhaft"
        }
    }

    /// UV-Index-Kategorie nach WHO-Skala.
    var uvCategory: String {
        switch uvIndex {
        case ..<3: return "niedrig"
        case ..<6: return "mässig"
        case ..<8: return "hoch"
        case ..<11: return "sehr hoch"
        default: return "extrem"
        }
    }
}

enum WeatherServiceError: GermanLocalizedError {
    case invalidURL
    /// HTTP-Fehlerstatus von Open-Meteo (z. B. 429 = Rate-Limit).
    case badResponse(status: Int)

    var errorDescription: String? { userMessage }

    /// Nutzerfreundlicher Hinweis für die UI.
    var userMessage: String {
        switch self {
        case .invalidURL:
            return "Wetter-Anfrage ungültig."
        case .badResponse(let status):
            if status == 429 {
                return "Wetter-Limit erreicht (429). Bitte später erneut versuchen."
            }
            return "Wetter konnte nicht geladen werden (Status \(status))."
        }
    }
}

final class WeatherService: Sendable {
    static let shared = WeatherService()

    private init() {}

    func fetchCurrentWeather(for coordinate: CLLocationCoordinate2D) async throws -> CurrentWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"
            ),
            // UV-Index gibt es bei Open-Meteo nur stündlich.
            URLQueryItem(name: "hourly", value: "uv_index"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else {
            throw WeatherServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw WeatherServiceError.badResponse(status: -1)
        }
        guard http.statusCode == 200 else {
            throw WeatherServiceError.badResponse(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return CurrentWeather(
            temperatureC: decoded.current.temperature2m,
            feelsLikeC: decoded.current.apparentTemperature,
            humidityPercent: decoded.current.relativeHumidity2m,
            uvIndex: Self.currentUVIndex(from: decoded),
            windSpeedKmh: decoded.current.windSpeed10m,
            weatherCode: decoded.current.weatherCode,
            isDay: decoded.current.isDay == 1
        )
    }

    /// UV-Index der aktuellen Stunde: der Eintrag in `hourly`, dessen Zeit-
    /// Stempel dieselbe Stunde wie `current.time` trägt (Fallback: erster Wert).
    private static func currentUVIndex(from response: OpenMeteoResponse) -> Double {
        guard let hourly = response.hourly else { return 0 }
        let hourPrefix = response.current.time.prefix(13) // "YYYY-MM-DDTHH"
        if let index = hourly.time.firstIndex(where: { $0.hasPrefix(hourPrefix) }),
           index < hourly.uvIndex.count {
            return hourly.uvIndex[index]
        }
        return hourly.uvIndex.first ?? 0
    }

    /// Ortsname (Stadt bzw. Quartier) zur Koordinate, nil wenn das
    /// Reverse-Geocoding fehlschlägt – die UI zeigt dann nur das Wetter.
    func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return placemark?.locality ?? placemark?.subLocality
    }
}

// MARK: - Open-Meteo DTO

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let hourly: Hourly?

    struct Current: Decodable {
        let time: String
        let temperature2m: Double
        let apparentTemperature: Double
        let relativeHumidity2m: Int
        let weatherCode: Int
        let windSpeed10m: Double
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let uvIndex: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case uvIndex = "uv_index"
        }
    }
}