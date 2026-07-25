// ARViewContainer.swift
// ARMikronav
//
// SwiftUI-Wrapper für RealityKit's ARView. Startet die Session via
// ARSessionService. Barrieren werden bewusst NICHT im AR-Raum gerendert
// (sauberes Kamerabild) – sie melden sich ausschließlich über
// das Warn-Banner. Im POI-Modus projiziert der Coordinator die
// GPS-Positionen der POIs in den Bildschirmraum; die Karten selbst rendert
// das SwiftUI-Overlay in ARModeView. Bei aktiver Navigation rendert der
// Coordinator zusätzlich die Route als Boden-Pfad (ARRouteRenderer).

import SwiftUI
import ARKit
import RealityKit
import CoreLocation

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var service: ARSessionService
    let origin: CLLocationCoordinate2D?
    var pois: [POI]
    var route: ActiveRoute?
    /// Geschätzte Höhe, in der das Gerät gehalten wird (aus dem UserProfile:
    /// Sitzhöhe + Oberkörper). Bestimmt, wie tief der Routen-Pfad unter dem
    /// Session-Ursprung auf den Boden gelegt wird.
    var deviceHeight: Float = ARRouteRenderer.defaultDeviceHeight
    let projector: ARPOIProjector

    func makeCoordinator() -> Coordinator {
        Coordinator(projector: projector)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )
        // Für eine Navigations-Overlay wird keine Foto-Realismus-Nachbearbeitung
        // gebraucht. Diese Effekte abschalten spart GPU-Last → gleichmässigere
        // Bildrate, weniger thermisches Drosseln über einen langen Testtag und
        // ein flüssigeres Bild bei Fahrt. Das Kamerabild selbst bleibt unberührt.
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disableHDR,
            .disableCameraGrain,
            .disableFaceMesh,
            .disablePersonOcclusion,
            .disableGroundingShadows
        ]
        context.coordinator.arView = arView
        context.coordinator.startProjecting()
        Task { await service.run(on: arView.session, at: origin) }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.origin = origin
        context.coordinator.pois = pois
        context.coordinator.route = route
        context.coordinator.deviceHeight = deviceHeight
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stopProjecting()
        uiView.session.pause()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        weak var arView: ARView?
        var origin: CLLocationCoordinate2D?
        var pois: [POI] = []
        var route: ActiveRoute?
        var deviceHeight: Float = ARRouteRenderer.defaultDeviceHeight

        private let projector: ARPOIProjector
        private var projectionTask: Task<Void, Never>?
        private var routeAnchor: AnchorEntity?
        private var renderedRouteID: UUID?

        /// Geglätteter Yaw-Korrekturwinkel (signierte Grad) der AR-Welt gegen
        /// echt-Nord und die daraus gebaute Drehung um +Y. Sie wird laufend an
        /// den Kompassfehler herangeführt und auf Route UND POIs angewendet.
        private var smoothedCorrectionDeg: Double?
        private var correctionQuat = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

        /// Von ARKit gemessene Boden-Y (Weltrahmen), sobald eine horizontale
        /// Ebene gefunden wurde – ersetzt die reine Höhenschätzung aus dem
        /// Profil. `nil`, solange noch keine Ebene erkannt ist.
        private var detectedGroundY: Float?

        init(projector: ARPOIProjector) {
            self.projector = projector
        }

        func startProjecting() {
            projectionTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }

        func stopProjecting() {
            projectionTask?.cancel()
            projectionTask = nil
        }

        private func tick() {
            updateHeadingCorrection()
            updateGroundDetection()
            syncRouteEntities()
            projectPOIs()
        }

        /// Vergleicht die AR-Blickrichtung der Kamera mit der echten
        /// (magnetkompass-unabhängigen) Kamera-Blickrichtung aus der Gerätelage
        /// und führt den Korrekturwinkel geglättet nach. Nur bei normalem
        /// Tracking und vorliegender echt-Nord-Richtung – so bleibt die
        /// Korrektur stabil (der Fehler der Sessionausrichtung ist konstant).
        private func updateHeadingCorrection() {
            guard let arView,
                  let frame = arView.session.currentFrame,
                  case .normal = frame.camera.trackingState,
                  let trueBearing = LocationService.shared.lookDirection
            else { return }

            let forward = ARHeadingCorrection.cameraForward(from: frame.camera.transform)
            guard let arYaw = ARHeadingCorrection.arYawDegrees(
                forwardEast: forward.x,
                forwardNorth: -forward.z
            ) else { return }

            let raw = ARHeadingCorrection.normalizedSignedDegrees(trueBearing - arYaw)
            let smoothed = ARHeadingCorrection.smooth(
                previous: smoothedCorrectionDeg,
                new: raw,
                factor: 0.1
            )
            smoothedCorrectionDeg = smoothed
            correctionQuat = simd_quatf(
                angle: Float(smoothed * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )
            // Bestehenden Routen-Anker sofort mitkorrigieren (er ist am
            // Weltursprung verankert, die Drehung um +Y dreht ihn um denselben
            // Punkt, um den die POIs projiziert werden).
            routeAnchor?.orientation = correctionQuat
        }

        /// Sucht einmalig die reale Bodenhöhe per Raycast auf eine erkannte
        /// horizontale Ebene. Gefunden → gemerkt und Route mit der echten
        /// Bodenhöhe neu aufbauen (statt der Höhenschätzung aus dem Profil).
        private func updateGroundDetection() {
            guard detectedGroundY == nil,
                  let arView,
                  arView.bounds.width > 0, arView.bounds.height > 0
            else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let hit = arView.raycast(
                from: center,
                allowing: .estimatedPlane,
                alignment: .horizontal
            ).first else { return }

            // Der Session-Ursprung (y = 0) liegt auf Gerätehöhe; ein plausibler
            // Boden liegt 0,3–2,5 m darunter. Ausreisser (fälschlich erkannte
            // Tisch-/Wandebene) verwerfen und später erneut versuchen.
            let candidate = hit.worldTransform.columns.3.y
            guard candidate < -0.3, candidate > -2.5 else { return }

            detectedGroundY = candidate
            // Route mit der gemessenen Bodenhöhe neu aufbauen.
            renderedRouteID = nil
        }

        /// Baut die Route-Entities neu auf, sobald sich die aktive Route
        /// ändert (Start, Ziel-Wechsel oder Stop) oder die reale Bodenhöhe
        /// erstmals bekannt ist. Der frische Anker übernimmt sofort die
        /// aktuelle Kompasskorrektur.
        private func syncRouteEntities() {
            guard let arView, let origin else { return }
            guard route?.id != renderedRouteID else { return }

            if let routeAnchor {
                arView.scene.removeAnchor(routeAnchor)
            }
            routeAnchor = nil
            renderedRouteID = route?.id

            guard let route else { return }
            let anchor = ARRouteRenderer.makeRouteAnchor(
                for: route,
                origin: origin,
                deviceHeight: deviceHeight,
                groundHeight: detectedGroundY
            )
            anchor.orientation = correctionQuat
            arView.scene.addAnchor(anchor)
            routeAnchor = anchor
        }

        private func projectPOIs() {
            guard let arView, let origin, !pois.isEmpty else {
                if !projector.projected.isEmpty {
                    projector.projected = []
                }
                return
            }

            let visibleBounds = arView.bounds.insetBy(dx: -80, dy: -80)
            var result: [ProjectedPOI] = []

            // Maximal die 8 nächsten POIs (Distanz zur AR-Origin), damit das
            // Bild nicht überladen wird – die Altstadt-Liste ist nach
            // Distanz zum Altstadt-Zentrum sortiert, nicht zum eigenen Standort.
            let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let nearestPOIs = pois
                .sorted {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                        .distance(from: originLocation)
                        < CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                            .distance(from: originLocation)
                }
                .prefix(8)

            for poi in nearestPOIs {
                let coordinate = CLLocationCoordinate2D(
                    latitude: poi.latitude,
                    longitude: poi.longitude
                )
                let worldPosition = ARGeoMapper.arPosition(
                    of: coordinate,
                    relativeTo: origin,
                    height: 0
                )
                // Gleiche Kompasskorrektur wie für die Route: Die POIs sind am
                // Weltursprung verankert, deshalb die Position um +Y drehen,
                // bevor sie in den Bildschirmraum projiziert wird.
                let corrected = correctionQuat.act(worldPosition)
                // project() liefert nil für Punkte hinter der Kamera.
                guard let screenPoint = arView.project(corrected) else { continue }
                guard visibleBounds.contains(screenPoint) else { continue }
                result.append(ProjectedPOI(poi: poi, point: screenPoint))
            }

            projector.projected = result
        }
    }
}