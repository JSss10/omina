// DraftProfile.swift
// Omina – Temporärer Profil-Draft während des Onboardings.
// Wird am Ende (Screen 1.6) in ein UserProfile umgewandelt und in Supabase gespeichert.

import Foundation

struct DraftProfile {
    // Profil-Setup – Vorbelegt aus Auth-user_metadata (Registrierung),
    // Pflicht bei Apple/Google Sign-in, wo kein Name miterfasst wird.
    var firstName: String = ""
    var lastName: String = ""

    var mobilityCategory: MobilityCategory?
    var wheelchairSubtype: WheelchairSubtype?

    // Masse – werden in Screen 1.3 mit Defaults aus wheelchairSubtype vorbelegt
    var widthCm: Int = 65
    var heightCm: Int = 130
    var seatHeightCm: Int = 50
    var lengthCm: Int = 120
    var weightKg: Int = 80

    // Eigenes Tempo (km/h) – Screen 1.4, vorbelegt aus wheelchairSubtype.
    // Grundlage für Fahrzeit/Ankunft statt des Fussgänger-Tempos der
    // Routing-Dienste.
    var travelSpeedKmh: Double = 3.5

    // Fähigkeiten – werden in Screen 1.4 mit Defaults aus wheelchairSubtype vorbelegt
    var maxIncline: Double = 6.0
    var maxCurbHeight: Double = 3.0
    var surfaceTolerance: SurfaceTolerance = .fineCobble
    var maneuverBufferCm: Int = 10

    // Unterstützung – Screen 1.5
    var companionStatus: CompanionStatus = .alwaysAlone
    var companionInclineBonus: Double = 3.0
    var companionCurbBonus: Double = 4.0

    // Eurokey-Besitz (Screen 1.5) – schaltet Eurokey-WCs als zugänglich frei
    var hasEurokey: Bool = false

    /// Gibt den internen Rollstuhltyp (5 Kategorien) für die Barrierenlogik zurück.
    var wheelchairType: WheelchairType? {
        wheelchairSubtype?.internalType
    }

    /// Übernimmt die Defaults eines Rollstuhl-Subtyps in die Masse- und Fähigkeiten-Felder.
    /// Wird aufgerufen, wenn in Screen 1.2 ein Subtyp ausgewählt wird.
    mutating func applyDefaults(for subtype: WheelchairSubtype) {
        let type = subtype.internalType
        widthCm = type.defaultWidth
        seatHeightCm = type.defaultSeatHeight
        lengthCm = type.defaultLength
        travelSpeedKmh = type.defaultSpeedKmh
        maxIncline = type.defaultMaxIncline
        maxCurbHeight = type.defaultMaxCurb
    }

    /// Validiert, ob der Draft vollständig genug ist, um ein UserProfile zu bauen.
    var isComplete: Bool {
        mobilityCategory != nil && wheelchairSubtype != nil
    }

    /// Wandelt den Draft in ein finales UserProfile um. Gibt nil zurück, wenn unvollständig.
    func buildUserProfile(userId: UUID) -> UserProfile? {
        guard let category = mobilityCategory,
              let type = wheelchairType else { return nil }

        let now = Date()
        return UserProfile(
            id: userId,
            mobilityCategory: category,
            wheelchairType: type,
            widthCm: widthCm,
            heightCm: heightCm,
            weightKg: weightKg,
            seatHeightCm: seatHeightCm,
            lengthCm: lengthCm,
            travelSpeedKmh: travelSpeedKmh,
            maxIncline: maxIncline,
            maxCurbHeight: maxCurbHeight,
            surfaceTolerance: surfaceTolerance,
            maneuverBufferCm: maneuverBufferCm,
            companionStatus: companionStatus,
            companionTodayOverride: false,
            companionInclineBonus: companionInclineBonus,
            companionCurbBonus: companionCurbBonus,
            hasEurokey: hasEurokey,
            createdAt: now,
            updatedAt: now
        )
    }
}