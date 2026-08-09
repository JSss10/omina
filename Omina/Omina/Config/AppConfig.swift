// AppConfig.swift
// Omina
//
// Öffentliche Konstanten der App – alles, was problemlos in Git stehen darf.
// Geheime Werte (Supabase-Keys, ginto-Bearer) liegen in Secrets.swift,
// das per .gitignore ausgeschlossen ist.

import Foundation
import CoreLocation

enum AppConfig {
    // MARK: - Testgebiet Altstadt Zürich
    static let testAreaMinLat = 47.369
    static let testAreaMaxLat = 47.375
    static let testAreaMinLng = 8.539
    static let testAreaMaxLng = 8.547

    // MARK: - Feldtest-Gebiet Kreis 1 Stadt Zürich
    // Bezugspunkt für den Feldtest (Altstadt: Rathaus, Hochschulen,
    // Lindenhof, City) und Wetter-Fallback ohne GPS-Fix.
    static let kreis1Center = CLLocationCoordinate2D(latitude: 47.3710, longitude: 8.5400)
    static let kreis1RadiusM: Double = 1400

    // MARK: - Abdeckung ganze Zürcher Altstadt (Stadtkreis 1)
    // Karte (POIs + Barrieren) und Homescreen laden die ganze Altstadt;
    // der Radius um den historischen Mittelpunkt (47° 22′ 13″ N / 8° 32′ 30″ O)
    // deckt die ~1,8 km² beidseits der Limmat vom Hauptbahnhof bis zum
    // Zürichsee ab (Quartiere Rathaus, Hochschulen, Lindenhof, City).
    static let altstadtCenter = CLLocationCoordinate2D(latitude: 47.3703, longitude: 8.5417)
    static let altstadtRadiusM: Double = 1_200

    // MARK: - Defaults
    static let defaultBarrierRadius: Double = 500
    static let approachWarningDistance: Double = 30

    // Umkreis (Meter) um den aktuellen Standort, innerhalb dessen Barrieren
    // UND POIs auf Karte und im AR-Modus angezeigt werden. Bewusst eng, damit
    // in der dichten Altstadt nur die unmittelbare Umgebung sichtbar ist und
    // die Ansicht nicht überladen wirkt; passt sich beim Bewegen an.
    static let nearbyDisplayRadiusM: Double = 50

    // So viele Orte zeigt ein Kategorie-Filter höchstens: die nächstgelegenen.
    // Auf der Karte, in der Suche und im AR-Bild wären alle Treffer einer
    // Kategorie in der dichten Altstadt unübersichtlich – gebraucht wird das,
    // was in Reichweite liegt. Bewusst eine Anzahl statt eines Radius: So
    // bleibt die Liste auch dort brauchbar, wo in unmittelbarer Nähe gerade
    // nichts dieser Kategorie ist.
    static let nearestCategoryLimit = 5

    // MARK: - ginto API (Endpoint ist öffentlich, der Bearer-Token nicht)
    static let gintoAPIEndpoint = "https://api.ginto.guide/graphql"

    // MARK: - ginto Rating Profile IDs (öffentlich, identifizieren nur Profile)
    static let gintoManualWheelchairID = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzc4"
    static let gintoPowerWheelchairID = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzc5"
    static let gintoScewoBroID = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzM5NTE"
    static let gintoPushchairID = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzgw"

    // MARK: - Auth
    // Länge des E-Mail-Einmalcodes (Bestätigung + Code-Login). Muss mit der
    // OTP-Länge im Supabase-Dashboard übereinstimmen (Authentication → Emails).
    static let emailOTPCodeLength = 8

    // MARK: - Deep Links
    // URL-Schema der App. Muss mit CFBundleURLSchemes in der Info.plist
    // übereinstimmen.
    static let urlScheme = "omina"

    /// Host des Wiederherstellungs-Links – daran erkennt die App, dass ein
    /// Link aus der Passwort-E-Mail geöffnet wurde.
    static let passwordResetHost = "password-reset"

    /// Ziel des Links in der "Passwort zurücksetzen"-E-Mail. Muss im
    /// Supabase-Dashboard unter Authentication → URL Configuration →
    /// Redirect URLs eingetragen sein, sonst weist Supabase die Umleitung ab.
    static let passwordResetRedirectURL = URL(string: "\(urlScheme)://\(passwordResetHost)")!

    // MARK: - Rechtliches
    // Die App verwendet Apples Standard-Lizenzvertrag für lizenzierte
    // Apps (Standard-EULA) statt eigener Nutzungsbedingungen.
    static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    // MARK: - Feldtest
    // Schaltet "Feldtest starten" auf dem Welcome-Screen frei (Testprofil-Auswahl
    // statt Registrierung) und die Erfassung in test_participants/test_events.
    // Nach den drei Testtagen wieder aus – im regulären Betrieb registrieren
    // sich Nutzer:innen normal.
    static let fieldTestModeEnabled = false
}