// BarrierLogicTests.swift
// ARMikronavTests
//
// Tests für shouldWarn() – die personalisierte Barrierenbewertung
// (Services/BarrierLogic.swift, FA-23 bis FA-26, NFA-15).
//
// Diese Funktion entscheidet, ob eine Barriere für ein Profil gewarnt wird.
// Fehler hier sind besonders heikel: eine ausbleibende Warnung schickt eine
// Person in ein Hindernis, eine überflüssige Warnung macht die App unbrauchbar.
// Getestet werden deshalb beide Richtungen – warnen und nicht warnen – und
// gezielt die Grenzwerte, an denen sich die Entscheidung dreht.

import Testing
import Foundation
@testable import ARMikronav

// Das Test-Target baut ohne MainActor-Standardisolation, die App-Typen
// aber mit. @MainActor hier hält die Aufrufe in dieselbe Isolation.
@MainActor
struct BarrierLogicTests {

    // MARK: - Vorlagen

    /// Profil mit gezielt überschreibbaren Werten; die Vorgaben entsprechen
    /// einem manuellen Rollstuhl ohne Begleitung.
    private func profile(
        wheelchairType: WheelchairType = .manual,
        widthCm: Int = 65,
        maneuverBufferCm: Int = 10,
        maxIncline: Double = 6,
        maxCurbHeight: Double = 3,
        surfaceTolerance: SurfaceTolerance = .fineCobble,
        companionStatus: CompanionStatus = .alwaysAlone,
        companionTodayOverride: Bool = false,
        companionInclineBonus: Double = 3,
        companionCurbBonus: Double = 4,
        wetConditionsToday: Bool = false,
        lowEnergyToday: Bool = false
    ) -> UserProfile {
        UserProfile(
            id: UUID(),
            mobilityCategory: .wheelchair,
            wheelchairType: wheelchairType,
            widthCm: widthCm,
            heightCm: 130,
            weightKg: 75,
            maxIncline: maxIncline,
            maxCurbHeight: maxCurbHeight,
            surfaceTolerance: surfaceTolerance,
            maneuverBufferCm: maneuverBufferCm,
            companionStatus: companionStatus,
            companionTodayOverride: companionTodayOverride,
            companionInclineBonus: companionInclineBonus,
            companionCurbBonus: companionCurbBonus,
            wetConditionsToday: wetConditionsToday,
            lowEnergyToday: lowEnergyToday,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func barrier(
        _ type: BarrierType,
        value: Double? = nil,
        subtype: String? = nil,
        valueSource: ValueSource = .measured
    ) -> Barrier {
        Barrier(
            id: UUID(),
            type: type,
            subtype: subtype,
            value: value,
            unit: nil,
            latitude: 47.3717,
            longitude: 8.5422,
            valueSource: valueSource,
            source: "osm",
            sourceId: "test",
            isActive: true,
            lastVerified: nil
        )
    }

    // MARK: - Fehlende Bordstein-Absenkung (FA-26)

    /// Eine fehlende Absenkung ist für jedes Profil ein Hindernis – auch für
    /// den Treppensteiger, der sonst alles nimmt.
    @Test func missingCurbAlwaysWarns() {
        for type in WheelchairType.allCases {
            #expect(
                shouldWarn(
                    barrier: barrier(.curbMissing),
                    profile: profile(wheelchairType: type)
                )
            )
        }
    }

    // MARK: - Treppen (FA-25, FA-47)

    /// Treppen stoppen jeden Rollstuhl ausser dem Treppensteiger.
    @Test func stepsWarnUnlessWheelchairClimbs() {
        for type in WheelchairType.allCases {
            let warns = shouldWarn(
                barrier: barrier(.steps, value: 5),
                profile: profile(wheelchairType: type)
            )
            #expect(warns == !type.canClimbStairs)
        }
    }

    /// Auch ohne bekannte Stufenzahl bleibt die Treppe eine Treppe.
    @Test func stepsWithoutCountStillWarn() {
        #expect(
            shouldWarn(barrier: barrier(.steps), profile: profile())
        )
    }

    // MARK: - Bordstein

    /// Unter dem eigenen Limit wird nicht gewarnt, darüber schon.
    @Test func curbWarnsOnlyAboveOwnLimit() {
        let manual = profile(maxCurbHeight: 3)

        #expect(!shouldWarn(barrier: barrier(.curb, value: 2), profile: manual))
        #expect(shouldWarn(barrier: barrier(.curb, value: 4), profile: manual))
    }

    /// Genau auf dem Limit ist der Bordstein noch passierbar – die Bedingung
    /// ist `>`, nicht `>=`.
    @Test func curbAtExactLimitDoesNotWarn() {
        #expect(
            !shouldWarn(
                barrier: barrier(.curb, value: 3),
                profile: profile(maxCurbHeight: 3)
            )
        )
    }

    /// Ohne Höhenangabe wird gewarnt (NFA-15: im Zweifel warnen).
    @Test func curbWithoutValueWarns() {
        #expect(shouldWarn(barrier: barrier(.curb), profile: profile()))
    }

    // MARK: - Steigung

    @Test func inclineWarnsOnlyAboveOwnLimit() {
        let manual = profile(maxIncline: 6)

        #expect(!shouldWarn(barrier: barrier(.incline, value: 4), profile: manual))
        #expect(shouldWarn(barrier: barrier(.incline, value: 8), profile: manual))
    }

    /// Der Unterschied zwischen gemessenem und geschätztem Wert entscheidet
    /// genau auf dem Limit: gemessen heisst «passt noch», geschätzt heisst
    /// «lieber warnen» (NFA-15).
    @Test func estimatedInclineAtLimitWarnsMeasuredDoesNot() {
        let manual = profile(maxIncline: 6)

        #expect(
            !shouldWarn(
                barrier: barrier(.incline, value: 6, valueSource: .measured),
                profile: manual
            )
        )
        #expect(
            shouldWarn(
                barrier: barrier(.incline, value: 6, valueSource: .estimated),
                profile: manual
            )
        )
    }

    @Test func inclineWithoutValueWarns() {
        #expect(shouldWarn(barrier: barrier(.incline), profile: profile()))
    }

    // MARK: - Engstelle

    /// Gebraucht wird die Rollstuhlbreite plus Manövrier-Spielraum: 65 + 10 cm.
    @Test func narrowWarnsBelowWidthPlusBuffer() {
        let manual = profile(widthCm: 65, maneuverBufferCm: 10)

        #expect(shouldWarn(barrier: barrier(.narrow, value: 70), profile: manual))
        #expect(!shouldWarn(barrier: barrier(.narrow, value: 80), profile: manual))
    }

    /// Genau auf der benötigten Breite passt es noch – die Bedingung ist `<`.
    @Test func narrowAtExactWidthDoesNotWarn() {
        #expect(
            !shouldWarn(
                barrier: barrier(.narrow, value: 75),
                profile: profile(widthCm: 65, maneuverBufferCm: 10)
            )
        )
    }

    /// Ein grösserer Spielraum macht dieselbe Engstelle zum Hindernis.
    @Test func largerManeuverBufferMakesSameGapBlocking() {
        let gap = barrier(.narrow, value: 80)

        #expect(!shouldWarn(barrier: gap, profile: profile(widthCm: 65, maneuverBufferCm: 10)))
        #expect(shouldWarn(barrier: gap, profile: profile(widthCm: 65, maneuverBufferCm: 20)))
    }

    @Test func narrowWithoutValueWarns() {
        #expect(shouldWarn(barrier: barrier(.narrow), profile: profile()))
    }

    // MARK: - Oberfläche

    /// Die Bewertung folgt der Oberflächen-Toleranz (siehe OSMSurfaceRating).
    @Test func surfaceFollowsTolerance() {
        let cobble = barrier(.surface, subtype: "cobblestone")

        #expect(shouldWarn(barrier: cobble, profile: profile(surfaceTolerance: .smoothOnly)))
        #expect(shouldWarn(barrier: cobble, profile: profile(surfaceTolerance: .fineCobble)))
        #expect(!shouldWarn(barrier: cobble, profile: profile(surfaceTolerance: .almostAll)))
    }

    /// Ohne Subtyp ist nicht bekannt, worum es geht – hier wird bewusst NICHT
    /// gewarnt (anders als bei Bordstein, Steigung und Engstelle). Gewarnt
    /// wird über die Tags, die tatsächlich erfasst sind.
    @Test func surfaceWithoutSubtypeDoesNotWarn() {
        #expect(!shouldWarn(barrier: barrier(.surface), profile: profile()))
    }

    /// Nässe verschiebt die Toleranz eine Stufe Richtung «nur glatt» – feines
    /// Pflaster wird damit zum Hindernis.
    @Test func wetConditionsTightenSurfaceTolerance() {
        let sett = barrier(.surface, subtype: "sett")

        #expect(
            !shouldWarn(
                barrier: sett,
                profile: profile(surfaceTolerance: .fineCobble, wetConditionsToday: false)
            )
        )
        #expect(
            shouldWarn(
                barrier: sett,
                profile: profile(surfaceTolerance: .fineCobble, wetConditionsToday: true)
            )
        )
    }

    // MARK: - Temporäres Hindernis

    @Test func temporaryObstacleAlwaysWarns() {
        for type in WheelchairType.allCases {
            #expect(
                shouldWarn(
                    barrier: barrier(.temporary),
                    profile: profile(wheelchairType: type)
                )
            )
        }
    }

    // MARK: - Tageszustände und Begleitung

    /// Wenig Energie senkt die Grundwerte um 20 %: aus 10 % Steigung werden 8 %.
    @Test func lowEnergyReducesLimitsByTwentyPercent() {
        let rested = profile(maxIncline: 10, lowEnergyToday: false)
        let tired = profile(maxIncline: 10, lowEnergyToday: true)

        #expect(rested.effectiveMaxIncline == 10)
        #expect(tired.effectiveMaxIncline == 8)

        // Eine Steigung von 9 % ist ausgeruht machbar, müde nicht mehr.
        let slope = barrier(.incline, value: 9)
        #expect(!shouldWarn(barrier: slope, profile: rested))
        #expect(shouldWarn(barrier: slope, profile: tired))
    }

    /// Der Begleit-Bonus kommt in voller Höhe dazu, nachdem der Energie-Malus
    /// auf den Grundwert gewirkt hat: (10 × 0,8) + 3 = 11.
    @Test func companionBonusAppliesAfterEnergyPenalty() {
        let tiredWithCompanion = profile(
            maxIncline: 10,
            companionTodayOverride: true,
            companionInclineBonus: 3,
            lowEnergyToday: true
        )

        #expect(tiredWithCompanion.effectiveMaxIncline == 11)
    }

    /// Begleitung zählt aus zwei Quellen: der Angabe für heute oder dem
    /// dauerhaften Status «meistens mit Begleitung».
    @Test func companionCountsFromOverrideOrStatus() {
        let alone = profile(maxCurbHeight: 3, companionStatus: .alwaysAlone)
        let todayOnly = profile(
            maxCurbHeight: 3,
            companionStatus: .alwaysAlone,
            companionTodayOverride: true
        )
        let usually = profile(maxCurbHeight: 3, companionStatus: .usually)

        #expect(alone.effectiveMaxCurb == 3)
        #expect(todayOnly.effectiveMaxCurb == 7) // 3 + 4
        #expect(usually.effectiveMaxCurb == 7)

        // «Manchmal» allein reicht nicht – gewarnt wird ohne Begleitung.
        let sometimes = profile(maxCurbHeight: 3, companionStatus: .sometimes)
        #expect(sometimes.effectiveMaxCurb == 3)
    }

    /// Mit Begleitung wird derselbe Bordstein passierbar.
    @Test func companionMakesCurbPassable() {
        let curb = barrier(.curb, value: 6)

        #expect(shouldWarn(barrier: curb, profile: profile(maxCurbHeight: 3)))
        #expect(
            !shouldWarn(
                barrier: curb,
                profile: profile(
                    maxCurbHeight: 3,
                    companionTodayOverride: true,
                    companionCurbBonus: 4
                )
            )
        )
    }

    /// Die benötigte Breite ist Rollstuhlbreite plus Spielraum.
    @Test func effectiveWidthAddsManeuverBuffer() {
        #expect(profile(widthCm: 65, maneuverBufferCm: 10).effectiveWidthNeeded == 75)
        #expect(profile(widthCm: 80, maneuverBufferCm: 0).effectiveWidthNeeded == 80)
    }

    // MARK: - generateWarning

    /// Ohne Warnung entsteht auch kein Warnobjekt.
    @Test func generateWarningReturnsNilWhenNotWarning() {
        let warning = generateWarning(
            barrier: barrier(.curb, value: 2),
            profile: profile(maxCurbHeight: 3),
            distance: 12
        )

        #expect(warning == nil)
    }

    /// Die Warnung nennt den Wert der Barriere und das eigene Limit – beide
    /// Zahlen zusammen machen die Entscheidung nachvollziehbar.
    @Test func generateWarningStatesBarrierValueAndOwnLimit() throws {
        let warning = try #require(
            generateWarning(
                barrier: barrier(.curb, value: 8),
                profile: profile(maxCurbHeight: 3),
                distance: 12
            )
        )

        #expect(warning.barrierValue.contains("8"))
        #expect(warning.userLimit.contains("3"))
        #expect(warning.distance == 12)
    }

    /// Bei Treppen gibt es kein Limit zum Vergleichen – die Warnung sagt
    /// stattdessen klar, dass der Weg nicht passierbar ist.
    @Test func generateWarningForStepsSaysImpassable() throws {
        let warning = try #require(
            generateWarning(
                barrier: barrier(.steps, value: 4),
                profile: profile(wheelchairType: .manual),
                distance: 5
            )
        )

        #expect(warning.barrierValue.contains("4"))
        #expect(warning.userLimit == "Nicht passierbar")
    }

    /// Eine mitgegebene Alternative bleibt an der Warnung hängen.
    @Test func generateWarningKeepsAlternative() throws {
        let alternative = Alternative(
            description: "20 m weiter östlich abgesenkt",
            direction: 90,
            distance: 20
        )

        let warning = try #require(
            generateWarning(
                barrier: barrier(.curbMissing),
                profile: profile(),
                distance: 30,
                alternative: alternative
            )
        )

        #expect(warning.alternative?.description == "20 m weiter östlich abgesenkt")
        #expect(warning.alternative?.distance == 20)
    }

    // MARK: - Stellvertreter-Barriere am selben Punkt

    /// Liegen mehrere Barrieren am selben Ort, gewinnt die schwerwiegendere
    /// Art – Treppe vor Engstelle vor Bordstein vor Oberfläche.
    @Test func severityRanksStepsHighest() {
        let steps = barrier(.steps, value: 3)
        let surface = barrier(.surface, subtype: "sett")

        #expect(steps.isMoreSevere(than: surface))
        #expect(!surface.isMoreSevere(than: steps))
    }

    /// Bei gleicher Art entscheidet der grössere Wert.
    @Test func severityPrefersLargerValueWithinSameType() {
        #expect(barrier(.curb, value: 8).isMoreSevere(than: barrier(.curb, value: 4)))
    }

    /// Bei gleicher Art und gleichem Wert bleibt die Wahl über Neuberechnungen
    /// hinweg stabil – sonst springt der Karten-Marker.
    @Test func severityIsStableForIdenticalBarriers() {
        let a = barrier(.curb, value: 5)
        let b = barrier(.curb, value: 5)

        // Genau eine der beiden Richtungen ist wahr, unabhängig davon, welche.
        #expect(a.isMoreSevere(than: b) != b.isMoreSevere(than: a))
    }
}