// UserProfile.swift
// ARMikronav – v2.0

import Foundation

struct UserProfile: Codable {
    let id: UUID
    var mobilityCategory: MobilityCategory
    var wheelchairType: WheelchairType
    var widthCm: Int
    var heightCm: Int
    var weightKg: Int
    /// Sitzhöhe: Oberkante Sitzfläche inkl. Kissen ab Boden.
    /// Bestimmt zusammen mit heightCm die geschätzte Kamerahöhe im AR-Modus.
    var seatHeightCm: Int = 50
    /// Gesamtlänge inkl. Fussstützen – relevant für Lifte und Wendeflächen.
    var lengthCm: Int = 120
    /// Eigene Reisegeschwindigkeit in km/h. Grundlage für Fahrzeit und
    /// Ankunftszeit einer Route: Routing-Dienste rechnen mit Fussgänger-Tempo
    /// (~5 km/h), was für Rollstuhlnutzende je nach Antrieb deutlich zu schnell
    /// oder zu langsam ist. Vorbelegt aus dem Rollstuhltyp, frei anpassbar.
    var travelSpeedKmh: Double = 3.5
    var maxIncline: Double
    var maxCurbHeight: Double
    var surfaceTolerance: SurfaceTolerance
    /// Manövrier-Spielraum, der bei Engstellen zur Rollstuhlbreite addiert wird.
    var maneuverBufferCm: Int = 10
    var companionStatus: CompanionStatus
    var companionTodayOverride: Bool
    /// Individueller Zugewinn mit Begleitperson.
    var companionInclineBonus: Double = 3.0
    var companionCurbBonus: Double = 4.0

    // Tages-Zustände + Ausstattung (Quick Wins aus der Persona-Analyse)
    var wetConditionsToday: Bool = false
    var lowEnergyToday: Bool = false
    var hasEurokey: Bool = false

    var createdAt: Date
    var updatedAt: Date

    var effectiveWidthNeeded: Int { widthCm + maneuverBufferCm }

    private var hasCompanion: Bool {
        companionTodayOverride || companionStatus == .usually
    }

    /// Reihenfolge: Energie-Malus (−20 %) wirkt nur auf den persönlichen
    /// Grundwert; der Begleit-Bonus kommt danach in voller Höhe dazu.
    var effectiveMaxIncline: Double {
        let base = lowEnergyToday ? maxIncline * 0.8 : maxIncline
        return hasCompanion ? base + companionInclineBonus : base
    }

    var effectiveMaxCurb: Double {
        let base = lowEnergyToday ? maxCurbHeight * 0.8 : maxCurbHeight
        return hasCompanion ? base + companionCurbBonus : base
    }

    /// Untere/obere Grenze der eingebbaren Geschwindigkeit (km/h) – schützt die
    /// Zeitberechnung vor unsinnigen Werten (0 km/h ⇒ unendliche Fahrzeit).
    static let minTravelSpeedKmh: Double = 1.0
    static let maxTravelSpeedKmh: Double = 15.0

    /// Geschwindigkeit, mit der Fahrzeit und Ankunft berechnet werden: der
    /// eigene Wert, an wenig-Energie-Tagen um 20 % reduziert (wie die übrigen
    /// Limits), begrenzt auf den plausiblen Bereich.
    var effectiveTravelSpeedKmh: Double {
        let base = lowEnergyToday ? travelSpeedKmh * 0.8 : travelSpeedKmh
        return min(max(base, Self.minTravelSpeedKmh), Self.maxTravelSpeedKmh)
    }

    /// Dieselbe Geschwindigkeit in Meter pro Sekunde (Rechengrösse für die
    /// Fahrzeit entlang einer Route).
    var effectiveTravelSpeedMS: Double { effectiveTravelSpeedKmh / 3.6 }

    /// Nässe verschiebt die Oberflächen-Toleranz eine Stufe Richtung "nur glatt".
    var effectiveSurfaceTolerance: SurfaceTolerance {
        guard wetConditionsToday else { return surfaceTolerance }
        switch surfaceTolerance {
        case .almostAll:  return .fineCobble
        case .fineCobble: return .smoothOnly
        case .smoothOnly: return .smoothOnly
        }
    }

    /// Geschätzte Höhe, in der das iPhone im Sitzen gehalten wird (Meter).
    /// Das Gerät liegt typischerweise auf ca. 70 % der Strecke zwischen
    /// Sitzfläche und Kopfoberkante (etwas unter Augenhöhe). Der AR-Pfad wird
    /// um diesen Betrag unter den Session-Ursprung gelegt, damit er unabhängig
    /// von Rollstuhlmodell und Körpergrösse auf dem Boden liegt.
    var arDeviceHeightM: Float {
        let seat = Float(seatHeightCm) / 100
        let head = Float(heightCm) / 100
        let estimated = seat + (head - seat) * 0.7
        return min(max(estimated, 0.7), 1.6)
    }
}

// Abwärtskompatible Dekodierung: Profile, die vor Einführung von Sitzhöhe,
// Länge, Spielraum, Begleit-Boni, eigener Geschwindigkeit sowie den
// Tages-Zuständen (Nässe, Energie, Eurokey) gespeichert wurden
// (UserDefaults / Supabase user_metadata), erhalten die bisherigen Fix-Werte
// bzw. die Defaults des Rollstuhltyps.
extension UserProfile {
    private enum LegacyKeys: String, CodingKey {
        case id, mobilityCategory, wheelchairType
        case widthCm, heightCm, weightKg, seatHeightCm, lengthCm
        case travelSpeedKmh
        case maxIncline, maxCurbHeight, surfaceTolerance, maneuverBufferCm
        case companionStatus, companionTodayOverride
        case companionInclineBonus, companionCurbBonus
        case wetConditionsToday, lowEnergyToday, hasEurokey
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LegacyKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mobilityCategory = try c.decode(MobilityCategory.self, forKey: .mobilityCategory)
        wheelchairType = try c.decode(WheelchairType.self, forKey: .wheelchairType)
        widthCm = try c.decode(Int.self, forKey: .widthCm)
        heightCm = try c.decode(Int.self, forKey: .heightCm)
        weightKg = try c.decode(Int.self, forKey: .weightKg)
        seatHeightCm = try c.decodeIfPresent(Int.self, forKey: .seatHeightCm)
            ?? wheelchairType.defaultSeatHeight
        lengthCm = try c.decodeIfPresent(Int.self, forKey: .lengthCm)
            ?? wheelchairType.defaultLength
        travelSpeedKmh = try c.decodeIfPresent(Double.self, forKey: .travelSpeedKmh)
            ?? wheelchairType.defaultSpeedKmh
        maxIncline = try c.decode(Double.self, forKey: .maxIncline)
        maxCurbHeight = try c.decode(Double.self, forKey: .maxCurbHeight)
        surfaceTolerance = try c.decode(SurfaceTolerance.self, forKey: .surfaceTolerance)
        maneuverBufferCm = try c.decodeIfPresent(Int.self, forKey: .maneuverBufferCm) ?? 10
        companionStatus = try c.decode(CompanionStatus.self, forKey: .companionStatus)
        companionTodayOverride = try c.decode(Bool.self, forKey: .companionTodayOverride)
        companionInclineBonus = try c.decodeIfPresent(Double.self, forKey: .companionInclineBonus) ?? 3.0
        companionCurbBonus = try c.decodeIfPresent(Double.self, forKey: .companionCurbBonus) ?? 4.0
        wetConditionsToday = try c.decodeIfPresent(Bool.self, forKey: .wetConditionsToday) ?? false
        lowEnergyToday = try c.decodeIfPresent(Bool.self, forKey: .lowEnergyToday) ?? false
        hasEurokey = try c.decodeIfPresent(Bool.self, forKey: .hasEurokey) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

enum MobilityCategory: String, Codable, CaseIterable {
    case none, wheelchair, visualImpairment, blind
    case hearingImpairment, deaf, walkingDisability
    case stroller, rollator, elderly
}

enum WheelchairType: String, Codable, CaseIterable {
    case manual, emotion, joystick, electric, stairClimbing

    var canClimbStairs: Bool { self == .stairClimbing }

    var defaultWidth: Int {
        switch self {
        case .manual, .emotion: return 65
        case .joystick: return 70
        case .electric, .stairClimbing: return 80
        }
    }

    var defaultMaxIncline: Double {
        switch self {
        case .manual: return 6.0
        case .emotion: return 9.0
        case .joystick, .electric, .stairClimbing: return 12.0
        }
    }

    var defaultMaxCurb: Double {
        switch self {
        case .manual: return 3.0
        case .emotion, .joystick: return 6.0
        case .electric, .stairClimbing: return 3.0
        }
    }

    /// Typische Sitzhöhe (Sitzfläche inkl. Kissen ab Boden) je Rollstuhltyp.
    var defaultSeatHeight: Int {
        switch self {
        case .manual, .emotion: return 50
        case .joystick, .electric: return 55
        case .stairClimbing: return 60
        }
    }

    /// Typische Reisegeschwindigkeit (km/h) je Rollstuhltyp als Startwert für
    /// das Profil. Handbetrieb liegt deutlich unter Fussgänger-Tempo (~5 km/h),
    /// motorisierte Stühle darüber; jede Person kann den Wert anpassen.
    var defaultSpeedKmh: Double {
        switch self {
        case .manual:        return 3.5
        case .emotion:       return 5.0
        case .joystick:      return 5.0
        case .electric:      return 6.0
        case .stairClimbing: return 5.0
        }
    }

    /// Typische Gesamtlänge inkl. Fussstützen je Rollstuhltyp.
    var defaultLength: Int {
        switch self {
        case .manual, .emotion: return 110
        case .joystick: return 120
        case .electric: return 125
        case .stairClimbing: return 110
        }
    }

    /// ginto Rating Profile ID für diesen Rollstuhltyp
    var gintoRatingProfileID: String {
        switch self {
        case .manual, .emotion, .joystick:
            return AppConfig.gintoManualWheelchairID
        case .electric:
            return AppConfig.gintoPowerWheelchairID
        case .stairClimbing:
            return AppConfig.gintoScewoBroID
        }
    }

    /// ginto-Profil-Schlüssel in accessibility_details (manual/power/scewo)
    /// für diesen Rollstuhltyp.
    var gintoRatingProfileKey: String {
        switch self {
        case .manual, .emotion, .joystick: return "manual"
        case .electric:                    return "power"
        case .stairClimbing:               return "scewo"
        }
    }
}

enum SurfaceTolerance: String, Codable, CaseIterable {
    case smoothOnly, fineCobble, almostAll
}

enum CompanionStatus: String, Codable, CaseIterable {
    case alwaysAlone, sometimes, usually
}