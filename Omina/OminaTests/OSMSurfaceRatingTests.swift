// OSMSurfaceRatingTests.swift
// OminaTests
//
// Tests für die Bewertung der OSM-Oberflächen-Tags (surface, smoothness,
// tracktype) gegen die persönliche Oberflächen-Toleranz – die Werte und
// Stufen stammen aus dem OSM-Wiki, Projekt Rollstuhl-Routing.

import Testing
import Foundation
@testable import Omina

// Das Test-Target baut ohne MainActor-Standardisolation, die App-Typen
// aber mit. @MainActor hier hält die Aufrufe in dieselbe Isolation.
@MainActor
struct OSMSurfaceRatingTests {

    // MARK: - surface=*

    /// Asphalt und Beton sind für jedes Profil in Ordnung.
    @Test func smoothSurfacesNeverBlock() {
        for tolerance in SurfaceTolerance.allCases {
            #expect(!OSMSurfaceRating.isBlocking(surface: "asphalt", tolerance: tolerance))
            #expect(!OSMSurfaceRating.isBlocking(surface: "concrete", tolerance: tolerance))
            #expect(!OSMSurfaceRating.isBlocking(surface: "paved", tolerance: tolerance))
        }
    }

    /// Kopfsteinpflaster (sett) ist nur für "nur glatte Beläge" ein Hindernis –
    /// wer feines Pflaster akzeptiert, kommt darüber.
    @Test func settBlocksOnlySmoothOnlyProfiles() {
        #expect(OSMSurfaceRating.isBlocking(surface: "sett", tolerance: .smoothOnly))
        #expect(!OSMSurfaceRating.isBlocking(surface: "sett", tolerance: .fineCobble))
        #expect(!OSMSurfaceRating.isBlocking(surface: "sett", tolerance: .almostAll))
    }

    /// Grobes Naturstein-Kopfsteinpflaster stoppt auch Profile mit feinem
    /// Pflaster, nicht aber "fast alles".
    @Test func coarseCobblestoneBlocksUpToFineCobble() {
        for surface in ["cobblestone", "cobblestone_coarse", "unhewn_cobblestone"] {
            #expect(OSMSurfaceRating.isBlocking(surface: surface, tolerance: .smoothOnly))
            #expect(OSMSurfaceRating.isBlocking(surface: surface, tolerance: .fineCobble))
            #expect(!OSMSurfaceRating.isBlocking(surface: surface, tolerance: .almostAll))
        }
    }

    /// Loser Untergrund ist für jedes Profil ein Hindernis.
    @Test func looseSurfacesBlockEveryProfile() {
        for surface in ["gravel", "sand", "ground", "grass", "mud"] {
            for tolerance in SurfaceTolerance.allCases {
                #expect(OSMSurfaceRating.isBlocking(surface: surface, tolerance: tolerance))
            }
        }
    }

    /// Pflastersteine (moderne, ebene Platten) bleiben auch für "nur glatt"
    /// befahrbar – sonst wäre in der Altstadt fast jeder Platz gesperrt.
    @Test func pavingStonesStayPassable() {
        #expect(!OSMSurfaceRating.isBlocking(surface: "paving_stones", tolerance: .smoothOnly))
        #expect(!OSMSurfaceRating.isBlocking(surface: "concrete_plates", tolerance: .smoothOnly))
    }

    /// Unbekannte Werte lösen keine Warnung aus – gewarnt wird nur, wo OSM
    /// tatsächlich etwas erfasst hat.
    @Test func unknownSurfaceDoesNotBlock() {
        #expect(!OSMSurfaceRating.isBlocking(surface: "irgendwas", tolerance: .smoothOnly))
    }

    // MARK: - smoothness=*

    /// Wiki: bis "intermediate" fährt ein Rollstuhl. Für "nur glatte Beläge"
    /// ist das schon zu viel, für die anderen Profile nicht.
    @Test func intermediateSmoothnessBlocksOnlySmoothOnly() {
        #expect(OSMSurfaceRating.isBlocking(smoothness: "intermediate", tolerance: .smoothOnly))
        #expect(!OSMSurfaceRating.isBlocking(smoothness: "intermediate", tolerance: .fineCobble))
        #expect(!OSMSurfaceRating.isBlocking(smoothness: "intermediate", tolerance: .almostAll))
    }

    /// "bad" braucht laut Wiki robuste Bereifung – nur noch "fast alles"
    /// kommt durch.
    @Test func badSmoothnessBlocksUpToFineCobble() {
        #expect(OSMSurfaceRating.isBlocking(smoothness: "bad", tolerance: .smoothOnly))
        #expect(OSMSurfaceRating.isBlocking(smoothness: "bad", tolerance: .fineCobble))
        #expect(!OSMSurfaceRating.isBlocking(smoothness: "bad", tolerance: .almostAll))
    }

    /// Ab "very_bad" ist für jedes Profil Schluss.
    @Test func veryBadSmoothnessBlocksEveryProfile() {
        for value in ["very_bad", "horrible", "very_horrible", "impassable"] {
            for tolerance in SurfaceTolerance.allCases {
                #expect(OSMSurfaceRating.isBlocking(smoothness: value, tolerance: tolerance))
            }
        }
    }

    @Test func goodSmoothnessNeverBlocks() {
        for value in ["excellent", "good"] {
            for tolerance in SurfaceTolerance.allCases {
                #expect(!OSMSurfaceRating.isBlocking(smoothness: value, tolerance: tolerance))
            }
        }
    }

    // MARK: - tracktype=*

    /// grade1 (befestigt) ist immer in Ordnung, ab grade2 (Kies) nur noch für
    /// Profile, die fast alles fahren.
    @Test func trackTypeFollowsWikiGrades() {
        for tolerance in SurfaceTolerance.allCases {
            #expect(!OSMSurfaceRating.isBlocking(trackType: "grade1", tolerance: tolerance))
        }
        #expect(OSMSurfaceRating.isBlocking(trackType: "grade2", tolerance: .smoothOnly))
        #expect(OSMSurfaceRating.isBlocking(trackType: "grade2", tolerance: .fineCobble))
        #expect(!OSMSurfaceRating.isBlocking(trackType: "grade2", tolerance: .almostAll))
        #expect(OSMSurfaceRating.isBlocking(trackType: "grade3", tolerance: .almostAll))
    }

    // MARK: - Subtypen aus dem Import

    /// Der Import legt Ebenheit und Wegequalität mit Präfix ab; die Bewertung
    /// muss sie auseinanderhalten können.
    @Test func subtypeDispatchHandlesPrefixes() {
        #expect(OSMSurfaceRating.isBlocking(subtype: "smoothness_bad", tolerance: .fineCobble))
        #expect(!OSMSurfaceRating.isBlocking(subtype: "smoothness_good", tolerance: .smoothOnly))
        #expect(OSMSurfaceRating.isBlocking(subtype: "tracktype_grade3", tolerance: .almostAll))
        #expect(OSMSurfaceRating.isBlocking(subtype: "sett", tolerance: .smoothOnly))
    }

    // MARK: - Zusammenspiel mit shouldWarn

    /// Die Barrieren-Warnung greift auf dieselbe Bewertung zurück.
    @Test func shouldWarnUsesSurfaceRating() {
        let barrier = Barrier(
            id: UUID(),
            type: .surface,
            subtype: "smoothness_very_bad",
            value: nil,
            unit: nil,
            latitude: 47.3717,
            longitude: 8.5422,
            valueSource: .measured,
            source: "osm",
            sourceId: "1",
            isActive: true,
            lastVerified: nil
        )
        var profile = UserProfile(
            id: UUID(),
            mobilityCategory: .wheelchair,
            wheelchairType: .electric,
            widthCm: 80,
            heightCm: 130,
            weightKg: 90,
            maxIncline: 12,
            maxCurbHeight: 3,
            surfaceTolerance: .almostAll,
            companionStatus: .alwaysAlone,
            companionTodayOverride: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        #expect(shouldWarn(barrier: barrier, profile: profile))

        // Nasses Wetter verschiebt die Toleranz eine Stufe – der Belag bleibt
        // ein Hindernis.
        profile.wetConditionsToday = true
        #expect(shouldWarn(barrier: barrier, profile: profile))
    }
}