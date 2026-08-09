// WheelchairSubtype.swift
// Omina – 15 öffentlich sichtbare Rollstuhl-Subtypen, gemappt auf die
// 5 internen WheelchairType-Kategorien, die von der Barrierenlogik verwendet werden.
// Mapping-Quelle: Expertengespräche Jasmin Polsini & Vanessa Grand (Phase 1)

import Foundation

enum WheelchairSubtype: String, Codable, CaseIterable, Identifiable {
    // MARK: - Manuell
    case activeManual       // Standard Aktivrollstuhl
    case rigidFrame         // Starrrahmen
    case foldingManual      // Faltrollstuhl
    case lightweight        // Leichtgewicht
    case sportManual        // Sportrollstuhl

    // MARK: - Manuell mit Zusatzantrieb
    case eMotion            // e-motion Nabenantrieb
    case smartDrive         // SmartDrive Zusatzantrieb
    case pullingDevice      // Zuggerät (Triride, Batec)

    // MARK: - Elektrorollstuhl mit Joystick
    case powerJoystick      // Elektrorollstuhl mit Joystick
    case powerCompact       // Kompakter Elektrorollstuhl

    // MARK: - Elektrorollstuhl
    case powerIndoor        // Indoor-Elektrorollstuhl
    case powerOutdoor       // Outdoor-Elektrorollstuhl
    case scooter            // E-Scooter / Mobilitätshilfe

    // MARK: - Treppensteiger
    case scewoBro           // Scewo BRO
    case iBot               // iBot

    var id: String { rawValue }

    /// Mapping auf die 5 internen Kategorien der Barrierenlogik.
    var internalType: WheelchairType {
        switch self {
        case .activeManual, .rigidFrame, .foldingManual, .lightweight, .sportManual:
            return .manual
        case .eMotion, .smartDrive, .pullingDevice:
            return .emotion
        case .powerJoystick, .powerCompact:
            return .joystick
        case .powerIndoor, .powerOutdoor, .scooter:
            return .electric
        case .scewoBro, .iBot:
            return .stairClimbing
        }
    }

    var displayName: String {
        switch self {
        case .activeManual:   return "Aktivrollstuhl"
        case .rigidFrame:     return "Starrrahmen"
        case .foldingManual:  return "Faltrollstuhl"
        case .lightweight:    return "Leichtgewicht"
        case .sportManual:    return "Sportrollstuhl"
        case .eMotion:        return "e-motion (Nabenantrieb)"
        case .smartDrive:     return "SmartDrive"
        case .pullingDevice:  return "Zuggerät (Triride, Batec)"
        case .powerJoystick:  return "Elektrorollstuhl mit Joystick"
        case .powerCompact:   return "Kompakter Elektrorollstuhl"
        case .powerIndoor:    return "Indoor-Elektrorollstuhl"
        case .powerOutdoor:   return "Outdoor-Elektrorollstuhl"
        case .scooter:        return "E-Scooter"
        case .scewoBro:       return "Scewo BRO"
        case .iBot:           return "iBot"
        }
    }

    var category: WheelchairCategory {
        switch self {
        case .activeManual, .rigidFrame, .foldingManual, .lightweight, .sportManual:
            return .manual
        case .eMotion, .smartDrive, .pullingDevice:
            return .manualAssisted
        case .powerJoystick, .powerCompact:
            return .powerJoystick
        case .powerIndoor, .powerOutdoor, .scooter:
            return .power
        case .scewoBro, .iBot:
            return .stairClimbing
        }
    }
}

enum WheelchairCategory: String, CaseIterable, Identifiable {
    case manual
    case manualAssisted
    case powerJoystick
    case power
    case stairClimbing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:         return "Manuell"
        case .manualAssisted: return "Manuell mit Zusatzantrieb"
        case .powerJoystick:  return "Elektrorollstuhl mit Joystick"
        case .power:          return "Elektrorollstuhl"
        case .stairClimbing:  return "Treppensteiger"
        }
    }

    var subtypes: [WheelchairSubtype] {
        WheelchairSubtype.allCases.filter { $0.category == self }
    }
}
