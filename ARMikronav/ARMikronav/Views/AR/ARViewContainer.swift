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
//
// Verankerung (Feldtest-Bug "Weg ist erst perfekt, verschwindet dann"):
// Route und POI-Karten werden aus GPS-Koordinaten RELATIV ZUM AKTUELLEN
// STANDORT berechnet. Sie dürfen deshalb nicht am Session-Ursprung hängen –
// der liegt dort, wo die AR-Session gestartet wurde. Wer 100 m weiterfährt,
// bekäme den Pfad sonst um genau diese 100 m versetzt (und nach einer
// Neuberechnung gar nicht mehr ins Bild). Anker und Projektion beziehen sich
// daher auf die aktuelle Kameraposition im AR-Weltrahmen; die Kompass-
// Korrektur dreht um denselben Punkt, also um die Person statt um einen weit
// entfernten Ursprung. Zusätzlich wird der Pfad nach einer gewissen
// Eigenbewegung (und bei neuer Route oder wiedergefundenem Tracking) frisch
// verankert, damit sich GPS-Drift nicht aufsummiert.

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
    /// Sitzhöhe + Oberkörper). Bestimmt, wie tief der Routen-Pfad unter der
    /// aktuellen Kamerahöhe auf den Boden gelegt wird.
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

        /// Länge des im AR-Bild dargestellten Routenabschnitts (Meter voraus).
        /// Weiter voraus ist im Kamerabild ohnehin nicht mehr erkennbar, und
        /// die ganze Route zu rendern kostet hunderte Entities.
        private static let renderAheadM: CLLocationDistance = 140
        /// Nach so viel Eigenbewegung wird der Pfad frisch verankert: Er rückt
        /// mit (das dargestellte Fenster wandert voraus) und die aufgelaufene
        /// Abweichung zwischen AR-Tracking und GPS wird zurückgesetzt.
        private static let reanchorDistanceM: CLLocationDistance = 12
        /// Mindestabstand zwischen zwei Neuverankerungen – ohne ihn liesse ein
        /// springender GPS-Fix den Pfad flackern.
        private static let reanchorIntervalS: TimeInterval = 3
        /// So weit darf die gemessene Bodenebene von der aus der Gerätehöhe
        /// geschätzten abweichen, bevor sie als veraltet gilt (Steigung,
        /// fälschlich erkannte Tisch-/Mauerkante).
        private static let groundToleranceM: Float = 0.8

        private let projector: ARPOIProjector
        private var projectionTask: Task<Void, Never>?
        /// Anker an der Kameraposition; darunter der Container, der die
        /// Kompass-Korrektur trägt, und darunter die Route-Elemente.
        private var routeAnchor: AnchorEntity?
        private var routeContainer: Entity?
        private var renderedRouteID: UUID?
        /// GPS-Standort, auf den der aktuelle Anker aufgebaut ist.
        private var anchoredOrigin: CLLocationCoordinate2D?
        /// Zeitpunkt der letzten Verankerung (Sperrzeit dazwischen).
        private var anchoredAt: Date?
        /// Lief das Tracking beim letzten Tick normal? Ein Wechsel von
        /// eingeschränkt zurück auf normal (Relokalisierung nach Unterbrechung)
        /// kann den Weltursprung verschoben haben → neu verankern.
        private var wasTrackingNormal = false
        /// Erzwingt die nächste Verankerung (Tracking wiedergefunden,
        /// Bodenhöhe erstmals gemessen).
        private var needsReanchor = false

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
            guard let arView, let frame = arView.session.currentFrame else { return }
            let cameraPosition = Self.position(of: frame.camera.transform)

            updateTrackingState(frame.camera.trackingState)
            updateHeadingCorrection(frame: frame)
            updateGroundDetection(cameraY: cameraPosition.y)
            syncRouteEntities(cameraPosition: cameraPosition, trackingState: frame.camera.trackingState)
            projectPOIs(cameraPosition: cameraPosition)
        }

        /// Position der Kamera im AR-Weltrahmen (vierte Spalte des Transforms).
        private static func position(of transform: simd_float4x4) -> SIMD3<Float> {
            SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
        }

        /// Merkt sich den Tracking-Zustand. Kommt das Tracking nach einer
        /// Unterbrechung zurück, wird neu verankert – ARKit kann die Welt
        /// dabei verschoben haben.
        private func updateTrackingState(_ state: ARCamera.TrackingState) {
            let isNormal: Bool
            if case .normal = state {
                isNormal = true
            } else {
                isNormal = false
            }
            if isNormal, !wasTrackingNormal {
                needsReanchor = true
            }
            wasTrackingNormal = isNormal
        }

        /// Vergleicht die AR-Blickrichtung der Kamera mit der echten
        /// (magnetkompass-unabhängigen) Kamera-Blickrichtung aus der Gerätelage
        /// und führt den Korrekturwinkel geglättet nach. Nur bei normalem
        /// Tracking und vorliegender echt-Nord-Richtung – so bleibt die
        /// Korrektur stabil (der Fehler der Sessionausrichtung ist konstant).
        private func updateHeadingCorrection(frame: ARFrame) {
            guard case .normal = frame.camera.trackingState,
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
            // Bestehenden Pfad sofort mitkorrigieren. Der Container sitzt im
            // Anker an der Kameraposition, die Drehung um +Y dreht den Pfad
            // also um die Person – genau wie die POI-Projektion.
            routeContainer?.orientation = correctionQuat
        }

        /// Sucht die reale Bodenhöhe per Raycast auf eine erkannte horizontale
        /// Ebene. Gefunden → gemerkt und Route mit der echten Bodenhöhe neu
        /// aufbauen (statt der Höhenschätzung aus dem Profil). Die Plausibilität
        /// wird relativ zur AKTUELLEN Kamerahöhe geprüft, damit sie auch nach
        /// einer Steigung noch stimmt.
        private func updateGroundDetection(cameraY: Float) {
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

            // Ein plausibler Boden liegt 0,3–2,5 m unter der Kamera. Ausreisser
            // (fälschlich erkannte Tisch-/Wandebene) verwerfen und später
            // erneut versuchen.
            let candidate = hit.worldTransform.columns.3.y
            guard candidate < cameraY - 0.3, candidate > cameraY - 2.5 else { return }

            detectedGroundY = candidate
            // Route mit der gemessenen Bodenhöhe neu aufbauen.
            needsReanchor = true
        }

        /// Bodenhöhe im Weltrahmen: die gemessene Ebene, solange sie zur
        /// aktuellen Kamerahöhe passt – sonst die Schätzung aus der Gerätehöhe
        /// des Profils (und neu messen).
        private func groundLevel(below cameraY: Float) -> Float {
            let estimated = cameraY - deviceHeight
            guard let detected = detectedGroundY else { return estimated }
            guard abs(detected - estimated) <= Self.groundToleranceM else {
                detectedGroundY = nil
                return estimated
            }
            return detected
        }

        /// Baut die Route-Entities neu auf, wenn nötig (siehe `needsRebuild`),
        /// und verankert sie an der aktuellen Kameraposition. Der frische
        /// Container übernimmt sofort die aktuelle Kompasskorrektur.
        private func syncRouteEntities(
            cameraPosition: SIMD3<Float>,
            trackingState: ARCamera.TrackingState
        ) {
            guard let arView else { return }

            // Keine Route (oder noch kein Standort) → alles abräumen.
            guard let route, let origin else {
                removeRouteAnchor(from: arView)
                return
            }
            // Ohne verlässliches Tracking wäre die Kameraposition unbrauchbar –
            // dann lieber den bestehenden Pfad stehen lassen.
            guard case .normal = trackingState else { return }
            guard needsRebuild(route: route, origin: origin) else { return }

            removeRouteAnchor(from: arView)

            let groundY = groundLevel(below: cameraPosition.y)
            // Nur den Weg rendern, der vor einem liegt – ab dem Punkt auf der
            // Route, der dem eigenen Standort am nächsten liegt.
            let coordinates = RouteService.upcomingCoordinates(
                of: route,
                from: origin,
                aheadM: Self.renderAheadM
            )
            let container = ARRouteRenderer.makeRouteEntity(
                for: route,
                origin: origin,
                coordinates: coordinates,
                groundY: groundY
            )
            container.orientation = correctionQuat

            // Anker auf Höhe des Weltursprungs, aber an der Stelle, an der man
            // GERADE steht: Die Route ist relativ zum Standort aufgebaut, und
            // die Kompass-Korrektur dreht damit um die eigene Position.
            let anchor = AnchorEntity(
                world: SIMD3<Float>(cameraPosition.x, 0, cameraPosition.z)
            )
            anchor.addChild(container)
            arView.scene.addAnchor(anchor)

            routeAnchor = anchor
            routeContainer = container
            renderedRouteID = route.id
            anchoredOrigin = origin
            anchoredAt = Date()
            needsReanchor = false
        }

        /// Muss der Pfad neu aufgebaut werden? Bei neuer Route, nach einem
        /// Tracking-/Boden-Ereignis oder sobald man sich weit genug bewegt hat
        /// (dann wandert das dargestellte Fenster mit und die Verankerung wird
        /// wieder auf den aktuellen GPS-Standort bezogen).
        private func needsRebuild(route: ActiveRoute, origin: CLLocationCoordinate2D) -> Bool {
            if routeAnchor == nil || route.id != renderedRouteID { return true }
            // Sperrzeit: ein springender GPS-Fix soll den Pfad nicht flackern
            // lassen (Ausnahme: erzwungene Neuverankerung).
            if let anchoredAt, Date().timeIntervalSince(anchoredAt) < Self.reanchorIntervalS,
               !needsReanchor {
                return false
            }
            if needsReanchor { return true }
            // Nur verlässliche Fixes dürfen den Pfad versetzen. In den engen
            // Gassen springt der Standort sonst um zig Meter und der Pfad
            // zappelte mit.
            guard LocationService.shared.hasReliableFix else { return false }
            guard let anchoredOrigin else { return true }
            let moved = CLLocation(
                latitude: anchoredOrigin.latitude,
                longitude: anchoredOrigin.longitude
            ).distance(
                from: CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            )
            return moved >= Self.reanchorDistanceM
        }

        private func removeRouteAnchor(from arView: ARView) {
            if let routeAnchor {
                arView.scene.removeAnchor(routeAnchor)
            }
            routeAnchor = nil
            routeContainer = nil
            renderedRouteID = nil
            anchoredOrigin = nil
            anchoredAt = nil
        }

        private func projectPOIs(cameraPosition: SIMD3<Float>) {
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
                // Versatz vom eigenen Standort zum POI (Meter Ost/Nord, auf
                // Kamerahöhe), mit derselben Kompasskorrektur wie die Route.
                let offset = ARGeoMapper.arPosition(
                    of: coordinate,
                    relativeTo: origin,
                    height: 0
                )
                let corrected = correctionQuat.act(offset)
                // Der Versatz gilt ab der aktuellen Kameraposition, nicht ab
                // dem Session-Ursprung – sonst wandern die Karten mit jedem
                // gefahrenen Meter aus dem Bild.
                let worldPosition = cameraPosition + corrected
                // project() liefert nil für Punkte hinter der Kamera.
                guard let screenPoint = arView.project(worldPosition) else { continue }
                guard visibleBounds.contains(screenPoint) else { continue }
                result.append(ProjectedPOI(poi: poi, point: screenPoint))
            }

            projector.projected = result
        }
    }
}