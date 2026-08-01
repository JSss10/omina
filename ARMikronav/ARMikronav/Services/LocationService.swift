// LocationService.swift
// ARMikronav
//
// Wrapper um CLLocationManager – publiziert aktuellen Standort und Autorisierungsstatus.
// Aktualisiert nur, wenn sich die Position um mindestens `distanceFilter` Meter geändert hat,
// damit der MapViewModel nicht bei jedem GPS-Tick neu lädt.

import Foundation
import Combine
import CoreLocation
import CoreMotion

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    /// Aktuelle Blickrichtung des Geräts in Grad (0 = Norden, im Uhrzeigersinn).
    /// Bevorzugt der (bereits deklinationskorrigierte) wahre Kurs; fällt auf
    /// den magnetischen zurück. `nil`, solange noch kein Kurs vorliegt.
    /// Basiert auf `CLHeading` (Oberkante des Geräts) – für den Kompass korrekt,
    /// aber bei aufrecht gehaltenem iPhone NICHT die Kamera-Blickrichtung.
    @Published private(set) var heading: CLLocationDirection?

    /// Richtung, in die die Rückkamera des iPhones zeigt (0 = Norden, im
    /// Uhrzeigersinn) – aus der Gerätelage (CoreMotion) berechnet, damit sie
    /// auch bei AUFRECHT gehaltenem Gerät stimmt (dort steht `heading`/Kompass
    /// ~90° daneben, weil er die Oberkante misst). `nil`, solange keine
    /// verlässliche Lage vorliegt (z. B. Gerät flach nach oben/unten).
    @Published private(set) var lookDirection: CLLocationDirection?

    /// Blickrichtung für den Standort-Kegel: bevorzugt die Kamera-Blickrichtung
    /// (funktioniert aufrecht), fällt auf den Magnetkompass zurück.
    var viewingDirection: CLLocationDirection? {
        lookDirection ?? heading
    }

    // MARK: - Güte der Standort-Fixes

    /// Horizontale Ungenauigkeit (Meter), bis zu der ein Fix uneingeschränkt
    /// verwendet wird. In den engen, hohen Altstadtgassen liefert das GPS
    /// regelmässig Ausreisser mit 50–100 m Fehler – ein solcher Fix landet
    /// schnell auf dem anderen Limmatufer, und eine von dort berechnete Route
    /// führt kilometerweit über die nächste Brücke, obwohl das Ziel nebenan ist.
    static let usableAccuracyM: CLLocationAccuracy = 50
    /// Notfall-Schwelle: So ungenau darf ein Fix höchstens sein, wenn sonst
    /// gar keiner vorliegt – lieber ein grober Standort als eine leere Karte.
    private static let fallbackAccuracyM: CLLocationAccuracy = 150
    /// Nach so langer Durststrecke ohne brauchbaren Fix wird auf die
    /// Notfall-Schwelle gelockert.
    private static let fallbackAfterS: TimeInterval = 20
    /// Maximales Alter eines Fixes. CoreLocation liefert beim Start sofort den
    /// zuletzt gespeicherten Fix – der kann Stunden alt und kilometerweit weg
    /// sein und würde die erste Route am falschen Ort beginnen lassen.
    private static let maxFixAgeS: TimeInterval = 15

    /// Zeitpunkt des letzten übernommenen Fixes (für die Lockerung).
    private var lastAcceptedFixAt: Date?

    /// Gemeldete Genauigkeit des aktuellen Fixes in Metern (nil ohne Fix).
    var locationAccuracyM: CLLocationAccuracy? {
        currentLocation?.horizontalAccuracy
    }

    /// Ist der aktuelle Fix genau genug, um darauf eine Route zu berechnen?
    var hasReliableFix: Bool {
        guard let accuracy = locationAccuracyM else { return false }
        return accuracy >= 0 && accuracy <= Self.usableAccuracyM
    }

    /// Entscheidet, ob ein eingehender Fix übernommen wird: gültig, aktuell
    /// und genau genug. Ohne (oder nach längerer Zeit ohne) brauchbaren Fix
    /// wird die Genauigkeitsschwelle gelockert, damit die App bedienbar bleibt.
    private func isUsable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) <= Self.maxFixAgeS else { return false }
        if location.horizontalAccuracy <= Self.usableAccuracyM { return true }
        guard location.horizontalAccuracy <= Self.fallbackAccuracyM else { return false }
        guard let lastAcceptedFixAt else { return true }
        return Date().timeIntervalSince(lastAcceptedFixAt) >= Self.fallbackAfterS
    }

    private let manager: CLLocationManager
    private let motionManager = CMMotionManager()

    /// Offene Warteschlangen für `requestAuthorizationAsync()`, die auf die
    /// Antwort im System-Dialog warten und im Delegate-Callback fortgesetzt werden.
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = Self.browsingDistanceFilterM
        manager.headingFilter = 2
    }

    /// Distanzfilter im Normalbetrieb (Karte, POIs) – spart Batterie, weil
    /// nicht jeder GPS-Tick durch die Anzeige-Logik läuft.
    private static let browsingDistanceFilterM: CLLocationDistance = 10
    /// Distanzfilter während einer aktiven Navigation. Dichtere Updates, damit
    /// Fortschritt, Kartendrehung und vor allem das Erkennen eines eigenen
    /// Wegs (statt der vorgeschlagenen Route) zeitnah reagieren.
    private static let navigationDistanceFilterM: CLLocationDistance = 4

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Schaltet die Standort-Updates auf Navigations- bzw. Normalbetrieb um
    /// (siehe Distanzfilter oben). Wird vom MapViewModel beim Start und Stopp
    /// einer Route aufgerufen.
    func setNavigationActive(_ active: Bool) {
        manager.distanceFilter = active
            ? Self.navigationDistanceFilterM
            : Self.browsingDistanceFilterM
    }

    /// Fragt die Standort-Berechtigung an und kehrt erst zurück, wenn die
    /// Person im System-Dialog geantwortet hat. So lassen sich die
    /// Onboarding-Prompts wirklich nacheinander abarbeiten. Ist der Status
    /// bereits entschieden, gibt es keinen Dialog und die Funktion kehrt sofort
    /// mit dem aktuellen Status zurück.
    func requestAuthorizationAsync() async -> CLAuthorizationStatus {
        guard authorizationStatus == .notDetermined else {
            return authorizationStatus
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Setzt alle wartenden `requestAuthorizationAsync()`-Aufrufe fort, sobald
    /// die Person geantwortet hat (Status nicht mehr `.notDetermined`).
    private func resumeAuthorizationWaiters(with status: CLAuthorizationStatus) {
        guard status != .notDetermined, !authorizationContinuations.isEmpty else { return }
        let pending = authorizationContinuations
        authorizationContinuations.removeAll()
        pending.forEach { $0.resume(returning: status) }
    }

    func startUpdating() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            startUpdatingHeading()
        default:
            break
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        stopCameraDirectionUpdates()
    }

    /// Startet die Kompass-Updates (für Karten- und AR-Kompass) und die
    /// Kamera-Blickrichtung (für den Standort-Kegel).
    func startUpdatingHeading() {
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        startCameraDirectionUpdates()
    }

    func stopUpdatingHeading() {
        manager.stopUpdatingHeading()
        stopCameraDirectionUpdates()
    }

    // MARK: - Kamera-Blickrichtung (CoreMotion)

    /// Liefert die Blickrichtung der Rückkamera aus der Gerätelage, echt-Nord-
    /// referenziert. Funktioniert unabhängig davon, ob das iPhone flach oder
    /// aufrecht gehalten wird.
    private func startCameraDirectionUpdates() {
        guard motionManager.isDeviceMotionAvailable,
              !motionManager.isDeviceMotionActive
        else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.showsDeviceMovementDisplay = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        motionManager.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: queue
        ) { [weak self] motion, _ in
            guard let motion,
                  let bearing = Self.cameraBearing(from: motion.attitude.rotationMatrix)
            else { return }
            Task { @MainActor in self?.lookDirection = bearing }
        }
    }

    private func stopCameraDirectionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    /// Konvention für Apples `CMAttitude.rotationMatrix`. Auf dem echten Gerät
    /// verifiziert: Die transponierte Ableitung (`false`, Referenz → Gerät,
    /// nutzt m31/m32) liefert die korrekte Kamera-Blickrichtung. Nur umstellen,
    /// falls der Kegel je gespiegelt/verdreht erscheinen sollte.
    private static let usesDeviceToReferenceMatrix = false

    /// Bearing (0 = Norden, im Uhrzeigersinn) der Kamera-Blickrichtung
    /// (Geräte-(−Z)-Achse) im Referenzrahmen `.xTrueNorthZVertical`
    /// (x = Nord, y = West, z = oben). Die (−Z)-Achse in Referenzkoordinaten ist
    /// die negierte dritte Spalte der Matrix: Nord = −m13, West = −m23 ⇒
    /// Ost = m23. Bei fast senkrecht gehaltenem Gerät (Kamera nach oben/unten)
    /// ist die horizontale Projektion zu klein/verrauscht → `nil`.
    private static func cameraBearing(from r: CMRotationMatrix) -> CLLocationDirection? {
        let north: Double
        let east: Double
        if usesDeviceToReferenceMatrix {
            north = -r.m13
            east = r.m23
        } else {
            // Transponierte Konvention (Referenz → Gerät).
            north = -r.m31
            east = r.m32
        }
        let magnitude = (north * north + east * east).squareRoot()
        guard magnitude > 0.2 else { return nil }
        var degrees = atan2(east, north) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    manager.startUpdatingHeading()
                }
            }
            self.resumeAuthorizationWaiters(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            // Veraltete (Cache beim Start) und stark verrauschte Fixes
            // verwerfen – sie sind die häufigste Ursache für Routen, die vom
            // falschen Ort aus berechnet werden.
            guard self.isUsable(latest) else { return }
            self.lastAcceptedFixAt = Date()
            self.currentLocation = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Ungültige Kurse (negative Genauigkeit) verwerfen; sonst wahren
        // Kurs bevorzugen, magnetischen als Fallback.
        guard newHeading.headingAccuracy >= 0 else { return }
        let direction = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = direction
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Stille Fehlerbehandlung – UI reagiert über fehlende currentLocation.
    }
}