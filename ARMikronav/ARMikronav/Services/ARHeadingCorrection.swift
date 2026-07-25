// ARHeadingCorrection.swift
// ARMikronav
//
// Korrigiert die Gier-Ausrichtung (Yaw) der AR-Welt gegenüber dem echten
// Norden. ARWorldTracking richtet die Welt beim Sessionstart EINMALIG über den
// Magnetkompass aus (worldAlignment = .gravityAndHeading). In den engen,
// eisenreichen Gassen der Altstadt liegt dieser Kompass-Norden oft mehrere Grad
// daneben und wird nie nachgeführt – die AR-Route zeigt dann z. B. "links",
// wo sie "rechts" müsste (Feldtest-Rückmeldung Tag 1).
//
// Idee: Die AR-Blickrichtung der Kamera (aus dem ARKit-Kameratransform, im
// AR-Weltrahmen: -Z = AR-Norden, +X = Ost) mit der echten, aus der Gerätelage
// (CoreMotion, echt-Nord) bestimmten Kamera-Blickrichtung vergleichen. Die
// Differenz ist der – bei fester Sessionausrichtung konstante – Fehler der
// AR-Welt, unabhängig davon, wohin man gerade schaut. Um genau diesen Winkel
// wird der Routen-Anker (und werden die projizierten POIs) gedreht, damit die
// AR-Führung wieder mit der Realität übereinstimmt.

import Foundation
import simd

enum ARHeadingCorrection {
    /// Vorwärtsrichtung (Blickrichtung) der Kamera im AR-Weltrahmen aus dem
    /// 4x4-Kameratransform: Die Kamera schaut entlang ihrer lokalen -Z-Achse;
    /// das ist die negierte dritte Spalte des Transforms.
    static func cameraForward(from transform: simd_float4x4) -> SIMD3<Float> {
        let z = transform.columns.2
        return SIMD3<Float>(-z.x, -z.y, -z.z)
    }

    /// AR-Blickrichtung der Kamera als Kompasskurs im AR-Weltrahmen
    /// (0 = AR-Norden = -Z, im Uhrzeigersinn). Nord-Komponente = -forward.z,
    /// Ost-Komponente = forward.x. Bei fast senkrecht gehaltener Kamera (Blick
    /// nach oben/unten) ist die horizontale Projektion zu klein → `nil`.
    static func arYawDegrees(forwardEast east: Float, forwardNorth north: Float) -> Double? {
        let magnitude = (east * east + north * north).squareRoot()
        guard magnitude > 0.05 else { return nil }
        var degrees = atan2(Double(east), Double(north)) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Korrekturwinkel (Radiant) um die vertikale Achse (+Y), mit dem der in
    /// echt-Nord-Koordinaten aufgebaute Routen-Anker in den – womöglich
    /// verdrehten – AR-Weltrahmen eingepasst wird. RealityKit dreht bei
    /// positivem +Y-Winkel gegen den Uhrzeigersinn (von oben betrachtet), ein
    /// Kompasskurs läuft im Uhrzeigersinn – deshalb ist die nötige
    /// Anker-Drehung ψ = (echt − ar) im +Y-Rahmen.
    static func correctionRadians(trueBearingDeg: Double, arYawDeg: Double) -> Float {
        let deltaDeg = normalizedSignedDegrees(trueBearingDeg - arYawDeg)
        return Float(deltaDeg * .pi / 180)
    }

    /// Exponentiell geglätteter, wrap-sicherer Winkel-Mittelwert für zirkuläre
    /// Grössen (Grad, signiert): Der neue Wert wird über die kürzeste
    /// Kreisrichtung an den bisherigen herangeführt, damit der ±180°-Übergang
    /// nicht springt. `nil` als bisheriger Wert übernimmt den neuen unverändert.
    /// `factor` ∈ (0,1]: kleiner = träger/ruhiger.
    static func smooth(previous: Double?, new: Double, factor: Double) -> Double {
        guard let previous else { return normalizedSignedDegrees(new) }
        let delta = normalizedSignedDegrees(new - previous)
        return normalizedSignedDegrees(previous + delta * factor)
    }

    /// Normiert einen Winkel auf (−180, 180] Grad.
    static func normalizedSignedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 { value += 360 }
        if value > 180 { value -= 360 }
        return value
    }
}