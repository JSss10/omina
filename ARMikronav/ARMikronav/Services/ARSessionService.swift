// ARSessionService.swift
// ARMikronav
//
// Konfiguriert und überwacht eine ARKit-Session.
// Versucht zuerst ARGeoTracking (GPS-verankerte AR-Inhalte); fällt zurück auf
// ARWorldTracking, wenn das Gerät kein GeoTracking unterstützt oder die Position
// nicht von Apple's Geo-Map abgedeckt ist.
//
// Hinweis: Apple's GeoTracking-Coverage umfasst aktuell ausgewählte Städte in den
// USA, UK, Kanada, Australien, Japan, Singapur, Deutschland usw.
// Die Schweiz ist nicht abgedeckt – für das Testgebiet Altstadt Zürich greift
// daher praktisch immer der WorldTracking-Fallback.
//
// Kamera-Qualität: Es wird bewusst das beste verfügbare Videoformat gewählt
// (höchste Bildrate, dann höchste Auflösung) plus Autofokus und – wo möglich –
// HDR. Höhere Bildrate reduziert Bewegungsunschärfe und hält das Tracking bei
// Fahrt im Rollstuhl stabil.
//
// Unterbrechungsfrei: Nach kurzen Unterbrechungen (Anruf, App im Hintergrund,
// Control Center) relokalisiert ARKit automatisch die bestehende Karte, statt
// hart zurückzusetzen; wiederherstellbare Session-Fehler starten die Session
// begrenzt oft neu, bevor der Fehler-State gezeigt wird.
//
// Keine Ebenen-Erkennung: Der Bodenpfad wird aus der Gerätehöhe und der
// Schwerkraft gelegt (siehe ARViewContainer), nicht aus erkannten Flächen.
// Auf Kopfsteinpflaster, nassem Belag oder im Schatten findet ARKit keine
// verlässliche Ebene – der Pfad hing damit am Untergrund und verschwand.
// Ohne planeDetection bleibt zudem mehr Rechenzeit fürs Tracking selbst.

import Foundation
import ARKit
import Combine
import CoreLocation

@MainActor
final class ARSessionService: NSObject, ObservableObject {
    enum SessionState: Equatable {
        case idle
        case starting
        case running(TrackingMode)
        case failed(String)
    }

    enum TrackingMode: Equatable {
        case geoTracking
        case worldTracking
    }

    @Published private(set) var sessionState: SessionState = .idle

    /// Für die automatische Wiederherstellung nach Session-Fehlern gemerkt.
    private weak var activeSession: ARSession?
    private var activeCoordinate: CLLocationCoordinate2D?
    /// Zähler laufender Neustart-Versuche; wird bei normalem Tracking (siehe
    /// cameraDidChangeTrackingState) zurückgesetzt, damit dauerhaft fehlende
    /// Sessions nicht in einer Neustart-Schleife landen.
    private var restartCount = 0
    private static let maxRestarts = 3

    /// Startet die übergebene ARSession mit dem bestmöglichen Tracking-Modus.
    /// - Parameters:
    ///   - session: die Session, die der ARView gehört (siehe ARViewContainer).
    ///   - coordinate: aktueller Userstandort. Wenn vorhanden, wird GeoTracking
    ///     für genau diesen Punkt geprüft.
    func run(on session: ARSession, at coordinate: CLLocationCoordinate2D? = nil) async {
        sessionState = .starting
        session.delegate = self
        activeSession = session
        activeCoordinate = coordinate

        if let coordinate, ARGeoTrackingConfiguration.isSupported {
            let available = await Self.geoTrackingAvailable(at: coordinate)
            if available {
                let config = ARGeoTrackingConfiguration()
                        Self.applyCameraQuality(
                    to: config,
                    formats: ARGeoTrackingConfiguration.supportedVideoFormats
                )
                session.run(config)
                sessionState = .running(.geoTracking)
                return
            }
        }

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        Self.applyCameraQuality(
            to: config,
            formats: ARWorldTrackingConfiguration.supportedVideoFormats
        )
        session.run(config)
        sessionState = .running(.worldTracking)
    }

    func pause(_ session: ARSession) {
        session.pause()
        sessionState = .idle
    }

    // MARK: - Kamera-Qualität

    /// Wählt das beste Videoformat für ein scharfes, flüssiges Kamerabild –
    /// auch bei Fahrt im Rollstuhl. Priorität: höchste Bildrate (weniger
    /// Bewegungsunschärfe, stabileres Tracking bei Bewegung), danach höchste
    /// Auflösung. Aktiviert zusätzlich Autofokus und – wo unterstützt – HDR
    /// (kontrastreiche Altstadt-Gassen mit Schatten und hellem Himmel).
    private static func applyCameraQuality(
        to config: ARConfiguration,
        formats: [ARConfiguration.VideoFormat]
    ) {
        if let best = formats.max(by: { lhs, rhs in
            if lhs.framesPerSecond != rhs.framesPerSecond {
                return lhs.framesPerSecond < rhs.framesPerSecond
            }
            let lhsPixels = lhs.imageResolution.width * lhs.imageResolution.height
            let rhsPixels = rhs.imageResolution.width * rhs.imageResolution.height
            return lhsPixels < rhsPixels
        }) {
            config.videoFormat = best
            config.videoHDRAllowed = best.isVideoHDRSupported
        }
        if let worldConfig = config as? ARWorldTrackingConfiguration {
            worldConfig.isAutoFocusEnabled = true
        }
    }

    // MARK: - Wiederherstellung

    /// Startet die zuletzt konfigurierte Session erneut (gleicher Standort,
    /// bester Modus). Genutzt nach wiederherstellbaren Session-Fehlern.
    private func restart() async {
        guard let session = activeSession else { return }
        await run(on: session, at: activeCoordinate)
    }

    private static func geoTrackingAvailable(at coordinate: CLLocationCoordinate2D) async -> Bool {
        await withCheckedContinuation { continuation in
            ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { available, _ in
                continuation.resume(returning: available)
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARSessionService: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            // Wiederherstellbare Fehler (z. B. worldTrackingFailed) begrenzt oft
            // automatisch neu starten, statt in einen Sackgassen-Fehler zu laufen.
            if let arError = error as? ARError,
               Self.isRecoverable(arError),
               self.restartCount < Self.maxRestarts {
                self.restartCount += 1
                await self.restart()
            } else {
                self.sessionState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        // Kurzzeitige Unterbrechung (Anruf, App im Hintergrund, Control Center):
        // ARKit pausiert und relokalisiert danach automatisch
        // (sessionShouldAttemptRelocalization). Bewusst kein Fehler-State.
    }

    nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        // Nach einer Unterbrechung versucht ARKit, die bestehende Karte
        // wiederzufinden, statt hart zurückzusetzen – die Session läuft
        // samt Routen- und POI-Verankerung nahtlos weiter.
        true
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // Sobald das Tracking wieder normal läuft, sind vorige Neustarts
        // "verbraucht" – Zähler zurücksetzen, damit eine spätere, unabhängige
        // Unterbrechung erneut die vollen Neustart-Versuche hat.
        if case .normal = camera.trackingState {
            Task { @MainActor in self.restartCount = 0 }
        }
    }

    /// Nur echte Sackgassen-Fehler (fehlende Berechtigung, nicht unterstützte
    /// Konfiguration, defekter Sensor) führen sofort zum Fehler-State; alles
    /// andere wird als vorübergehend behandelt und neu gestartet.
    private static func isRecoverable(_ error: ARError) -> Bool {
        switch error.code {
        case .cameraUnauthorized, .microphoneUnauthorized, .locationUnauthorized,
             .unsupportedConfiguration, .sensorUnavailable, .sensorFailed:
            return false
        default:
            return true
        }
    }
}