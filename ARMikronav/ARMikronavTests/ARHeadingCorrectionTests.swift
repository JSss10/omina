// ARHeadingCorrectionTests.swift
// ARMikronavTests
//
// Tests für die Yaw-Korrektur der AR-Welt gegen echt-Nord: AR-Blickrichtung
// aus dem Kameravektor, Korrekturwinkel, wrap-sichere Winkelnormierung und
// geglätteter, zirkulärer Mittelwert.

import Testing
import simd
@testable import ARMikronav

struct ARHeadingCorrectionTests {

    // MARK: - AR-Yaw aus der Kamera-Vorwärtsrichtung

    @Test func arYawForCardinalForwards() {
        // Nord = -Z ⇒ forward (0,0,-1): forwardNorth = -(-1) = 1.
        #expect(ARHeadingCorrection.arYawDegrees(forwardEast: 0, forwardNorth: 1).map { abs($0) < 0.001 } == true)
        // Ost ⇒ forwardEast = 1.
        #expect(ARHeadingCorrection.arYawDegrees(forwardEast: 1, forwardNorth: 0).map { abs($0 - 90) < 0.001 } == true)
        // Süd ⇒ forwardNorth = -1.
        #expect(ARHeadingCorrection.arYawDegrees(forwardEast: 0, forwardNorth: -1).map { abs($0 - 180) < 0.001 } == true)
        // West ⇒ forwardEast = -1 ⇒ 270°.
        #expect(ARHeadingCorrection.arYawDegrees(forwardEast: -1, forwardNorth: 0).map { abs($0 - 270) < 0.001 } == true)
    }

    /// Fast senkrecht gehaltenes Gerät (keine horizontale Komponente): kein Yaw.
    @Test func arYawIsNilWhenVertical() {
        #expect(ARHeadingCorrection.arYawDegrees(forwardEast: 0, forwardNorth: 0) == nil)
    }

    // MARK: - Kamera-Vorwärtsvektor aus dem Transform

    /// Identitäts-Transform: Kamera schaut entlang -Z.
    @Test func cameraForwardOfIdentityIsMinusZ() {
        let forward = ARHeadingCorrection.cameraForward(from: matrix_identity_float4x4)
        #expect(abs(forward.x) < 0.001)
        #expect(abs(forward.y) < 0.001)
        #expect(abs(forward.z + 1) < 0.001)
    }

    // MARK: - Korrekturwinkel

    /// AR-Norden 10° zu klein (arYaw 350 bei echt 0): Korrektur +10°.
    @Test func correctionRadiansCompensatesOffset() {
        let radians = ARHeadingCorrection.correctionRadians(trueBearingDeg: 0, arYawDeg: 350)
        #expect(abs(Double(radians) - 10 * .pi / 180) < 0.001)
    }

    @Test func correctionRadiansIsZeroWhenAligned() {
        let radians = ARHeadingCorrection.correctionRadians(trueBearingDeg: 42, arYawDeg: 42)
        #expect(abs(Double(radians)) < 0.001)
    }

    // MARK: - Winkelnormierung

    @Test func normalizedSignedDegreesWraps() {
        #expect(abs(ARHeadingCorrection.normalizedSignedDegrees(350) + 10) < 0.001)
        #expect(abs(ARHeadingCorrection.normalizedSignedDegrees(-350) - 10) < 0.001)
        #expect(abs(ARHeadingCorrection.normalizedSignedDegrees(190) + 170) < 0.001)
        #expect(abs(ARHeadingCorrection.normalizedSignedDegrees(180) - 180) < 0.001)
    }

    // MARK: - Geglätteter, zirkulärer Mittelwert

    @Test func smoothTakesNewWhenNoPrevious() {
        #expect(abs(ARHeadingCorrection.smooth(previous: nil, new: 12, factor: 0.1) - 12) < 0.001)
    }

    @Test func smoothMovesFractionTowardsNew() {
        #expect(abs(ARHeadingCorrection.smooth(previous: 0, new: 10, factor: 0.5) - 5) < 0.001)
    }

    /// Über den 0°/360°-Übergang wird auf kürzestem Weg gemittelt (kein Sprung).
    @Test func smoothIsWrapSafeAroundZero() {
        // -10° (=350°) und +10°: Mittel bei 0°, nicht bei 170°.
        #expect(abs(ARHeadingCorrection.smooth(previous: -10, new: 10, factor: 0.5)) < 0.001)
    }

    /// Über den ±180°-Übergang wird ebenfalls auf kürzestem Weg gemittelt.
    @Test func smoothIsWrapSafeAroundOneEighty() {
        // 170° und 190°(=-170°): Mittel bei 180°.
        #expect(abs(ARHeadingCorrection.smooth(previous: 170, new: -170, factor: 0.5) - 180) < 0.001)
    }
}