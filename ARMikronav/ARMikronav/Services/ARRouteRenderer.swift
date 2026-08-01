// ARRouteRenderer.swift
// ARMikronav
//
// Baut die RealityKit-Entities für die AR-Routenführung: ein halbtransparenter
// Pfad auf Bodenhöhe entlang der Route, weisse Richtungs-Chevrons in
// regelmässigem Abstand und ein Ziel-Marker. Die GPS-Wegpunkte werden über
// ARGeoMapper in Meter Ost/Nord relativ zu `origin` abgebildet.
//
// Wichtig: Die erzeugte Entity ist RELATIV zum Standort aufgebaut (origin
// liegt im Ursprung 0/0). Der Aufrufer hängt sie an einen Anker an der
// aktuellen Kameraposition – nur so liegt der Pfad auch dann richtig, wenn
// man sich seit dem Sessionstart fortbewegt hat (siehe ARViewContainer).

import Foundation
import RealityKit
import CoreLocation
import UIKit
import simd

enum ARRouteRenderer {
    /// Fallback, falls kein Profil verfügbar ist: iPhone ~1.4 m über Boden.
    /// Der Boden liegt um diesen Betrag unter der aktuellen Kamerahöhe.
    static let defaultDeviceHeight: Float = 1.4
    static let pathWidth: Float = 0.8
    static let chevronSpacing: Float = 4
    static let maxChevrons = 80
    /// Maximaler Abstand der aus GPS abgeleiteten Wegpunkte (Meter). Dichtere
    /// Stützpunkte lassen den Pfad der Gasse folgen statt lange Segmente zu
    /// überspringen (siehe RouteService.densify).
    static let waypointSpacing: Float = 2
    /// Höhe, in der die weissen Richtungs-Pfeile ÜBER der Pfadoberfläche liegen
    /// (Meter). Die Pfeile sollen direkt auf dem violetten Weg liegen; ein
    /// kleiner Abstand verhindert lediglich Z-Fighting mit dem Teppich.
    static let chevronFloatHeight: Float = 0.03

    /// Bis zu diesem Abstand (Meter) vom Ende des dargestellten Abschnitts gilt
    /// das Ziel als erreicht dargestellt – nur dann wird der Ziel-Marker
    /// gesetzt. Sonst stünde die Zielstange am willkürlichen Ende des
    /// dargestellten Fensters statt am tatsächlichen Ziel.
    private static let destinationVisibleToleranceM: CLLocationDistance = 25

    /// Erzeugt die Entity mit allen Route-Elementen, aufgebaut RELATIV zu
    /// `origin` (Standort im Ursprung). `coordinates` ist der darzustellende
    /// Abschnitt der Route (siehe RouteService.upcomingCoordinates); `groundY`
    /// ist die Höhe des Bodens im Weltrahmen – entweder von ARKit gemessen
    /// oder aus der Gerätehöhe des Profils abgeleitet. So liegt der Pfad für
    /// jede Person individuell auf dem realen Boden.
    static func makeRouteEntity(
        for route: ActiveRoute,
        origin: CLLocationCoordinate2D,
        coordinates: [CLLocationCoordinate2D],
        groundY: Float
    ) -> Entity {
        let container = Entity()

        // Wegpunkte aus GPS verdichten (dichter Bodenpfad, gleichmässige
        // Chevron-Abstände), dann relativ zum Standort abbilden.
        let densified = RouteService.densify(
            coordinates,
            maxSpacingM: CLLocationDistance(waypointSpacing)
        )
        let points = densified.map {
            ARGeoMapper.arPosition(of: $0, relativeTo: origin, height: groundY)
        }

        // Ziel-Marker nur, wenn der dargestellte Abschnitt bis zum Ziel reicht.
        let showsDestination = coordinates.last.map { last in
            CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(
                    from: CLLocation(
                        latitude: route.destinationCoordinate.latitude,
                        longitude: route.destinationCoordinate.longitude
                    )
                ) <= destinationVisibleToleranceM
        } ?? false

        guard points.count >= 2 else {
            if showsDestination {
                addDestinationMarker(to: container, for: route, origin: origin, groundY: groundY)
            }
            return container
        }

        addCarpet(to: container, along: points)
        addChevrons(to: container, along: points, groundY: groundY)
        if showsDestination {
            addDestinationMarker(to: container, for: route, origin: origin, groundY: groundY)
        }
        return container
    }

    // MARK: - Pfad

    /// Zusammenhängender violetter Weg: Zwischen den Wegpunkten liegen flache
    /// Segmente, an jeder Richtungsänderung und an beiden Enden eine runde
    /// Scheibe. So verschmelzen die Segmente ohne Lücke zu einem durchgehenden
    /// Pfad mit runden Ecken und Enden (statt eckig abgeschnittener Stücke).
    private static func addCarpet(to container: Entity, along points: [SIMD3<Float>]) {
        let material = unlitMaterial(color: pathColor, opacity: 0.6)
        let disc = discMesh(radius: pathWidth / 2)

        // Gerade Segmente.
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            let delta = end - start
            let length = simd_length(SIMD2(delta.x, delta.z))
            guard length > 0.05 else { continue }

            let segment = ModelEntity(
                mesh: .generateBox(width: pathWidth, height: 0.02, depth: length),
                materials: [material]
            )
            segment.position = (start + end) / 2
            segment.orientation = simd_quatf(angle: atan2(delta.x, delta.z), axis: [0, 1, 0])
            container.addChild(segment)
        }

        // Runde Kappen an Start und Ziel plus runde Füllstücke an den Ecken,
        // damit der Pfad ununterbrochen und weich gerundet wirkt.
        func addDisc(at point: SIMD3<Float>) {
            let entity = ModelEntity(mesh: disc, materials: [material])
            // Minimal über der Teppichoberkante, um Z-Fighting zu vermeiden.
            entity.position = SIMD3(point.x, point.y + 0.012, point.z)
            container.addChild(entity)
        }

        if let first = points.first { addDisc(at: first) }
        if points.count > 1, let last = points.last { addDisc(at: last) }

        // An jeder nennenswerten Richtungsänderung eine Scheibe als runde Ecke.
        guard points.count > 2 else { return }
        for i in 1..<(points.count - 1) {
            let inDir = points[i] - points[i - 1]
            let outDir = points[i + 1] - points[i]
            let inLen = simd_length(SIMD2(inDir.x, inDir.z))
            let outLen = simd_length(SIMD2(outDir.x, outDir.z))
            guard inLen > 0.05, outLen > 0.05 else { continue }
            let a = SIMD2(inDir.x, inDir.z) / inLen
            let b = SIMD2(outDir.x, outDir.z) / outLen
            // cos des Winkels zwischen den Segmenten; < ~0.99 ≈ > 8° Richtungswechsel.
            if simd_dot(a, b) < 0.99 {
                addDisc(at: points[i])
            }
        }
    }

    /// Flache, runde Scheibe in der XZ-Ebene (Normale +Y), beidseitig sichtbar –
    /// für runde Pfad-Enden und weiche Ecken.
    private static func discMesh(radius: Float, segments: Int = 24) -> MeshResource {
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)]
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            positions.append(SIMD3<Float>(cos(angle) * radius, 0, sin(angle) * radius))
        }

        var indices: [UInt32] = []
        for i in 1...segments {
            let outer = UInt32(i)
            let next = UInt32(i + 1)
            // Vorder- und Rückseite, damit die Scheibe unabhängig von der
            // Blickrichtung (Face-Culling) immer sichtbar bleibt.
            indices += [0, outer, next]
            indices += [0, next, outer]
        }

        var descriptor = MeshDescriptor(name: "routeDisc")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(
            [SIMD3<Float>](repeating: [0, 1, 0], count: positions.count)
        )
        descriptor.primitives = .triangles(indices)

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return .generatePlane(width: radius * 2, depth: radius * 2)
    }

    // MARK: - Richtungs-Chevrons

    private static func addChevrons(
        to container: Entity,
        along points: [SIMD3<Float>],
        groundY: Float
    ) {
        let mesh = chevronMesh()
        let material = unlitMaterial(color: .white, opacity: 0.95)

        // Die weissen Pfeile liegen direkt auf dem violetten Weg – nur ein
        // kleiner Abstand über der Teppichoberkante verhindert Z-Fighting.
        let floatY = groundY + chevronFloatHeight

        var travelled: Float = 0
        var nextChevronAt: Float = 2
        var count = 0

        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            let delta = end - start
            let length = simd_length(SIMD2(delta.x, delta.z))
            guard length > 0.05 else { continue }
            let direction = delta / length
            let yaw = atan2(direction.x, direction.z)

            while nextChevronAt <= travelled + length, count < maxChevrons {
                let position = start + direction * (nextChevronAt - travelled)
                let chevron = ModelEntity(mesh: mesh, materials: [material])
                chevron.position = SIMD3(position.x, floatY, position.z)
                chevron.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                container.addChild(chevron)
                nextChevronAt += chevronSpacing
                count += 1
            }
            travelled += length
        }
    }

    /// Flaches Chevron ("∧") in der XZ-Ebene, Spitze zeigt Richtung +Z
    /// (wird per Yaw auf die Laufrichtung gedreht), Normale +Y.
    private static func chevronMesh() -> MeshResource {
        let positions: [SIMD3<Float>] = [
            [-0.22, 0, -0.05],  // 0: äusseres Ende links
            [0, 0, 0.15],       // 1: äussere Spitze
            [0.22, 0, -0.05],   // 2: äusseres Ende rechts
            [0.22, 0, -0.17],   // 3: inneres Ende rechts
            [0, 0, 0.03],       // 4: innere Spitze
            [-0.22, 0, -0.17],  // 5: inneres Ende links
        ]
        var descriptor = MeshDescriptor(name: "routeChevron")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(
            [SIMD3<Float>](repeating: [0, 1, 0], count: positions.count)
        )
        descriptor.primitives = .triangles([
            0, 1, 4,
            0, 4, 5,
            1, 2, 3,
            1, 3, 4,
        ])

        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        // Fallback, falls die Mesh-Generierung fehlschlägt.
        return .generatePlane(width: 0.4, depth: 0.3)
    }

    // MARK: - Ziel-Marker

    private static func addDestinationMarker(
        to container: Entity,
        for route: ActiveRoute,
        origin: CLLocationCoordinate2D,
        groundY: Float
    ) {
        let base = ARGeoMapper.arPosition(
            of: route.destinationCoordinate,
            relativeTo: origin,
            height: groundY
        )
        let poleHeight: Float = 1.8

        let marker = Entity()
        marker.position = base

        let pole = ModelEntity(
            mesh: .generateBox(width: 0.04, height: poleHeight, depth: 0.04),
            materials: [unlitMaterial(color: .white, opacity: 0.9)]
        )
        pole.position = [0, poleHeight / 2, 0]
        marker.addChild(pole)

        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.16),
            materials: [unlitMaterial(color: pathColor, opacity: 1)]
        )
        head.position = [0, poleHeight + 0.16, 0]
        marker.addChild(head)

        container.addChild(marker)
    }

    // MARK: - Material

    private static var pathColor: UIColor {
        UIColor(named: "Violet500") ?? .systemPurple
    }

    private static func unlitMaterial(color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }
}