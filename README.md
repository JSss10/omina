# AR-Mikronavigation

> AR-gestützte Mikronavigation für Rollstuhlnutzende – Entscheidungsunterstützung in barrierekritischen urbanen Situationen: iOS-Client, Web-Dashboard und eine gemeinsame Datenschicht.

## Über das Projekt

Die iOS-App visualisiert situative Barrieren (Stufen, Steigungen, Engstellen, Oberflächen) in Echtzeit über ARKit und zeigt die Zugänglichkeit von Points of Interest im Kamerabild an. Die Barrierenbewertung ist **personalisiert** – die App warnt nur, wenn eine Barriere für das individuelle Profil der Nutzer:in nicht passierbar ist.

Das System besteht aus drei Teilen um eine gemeinsame Datenschicht:

| Teil                                          | Rolle                                                                                                                  |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Datenschicht** (`Database/`, `migrations/`) | PostgreSQL + PostGIS auf Supabase: Datenmodell, Geo-Abfragen als API-Endpunkte, Zugriffsregeln über Row Level Security |
| **iOS-Client** (`ARMikronav/`)                | Karte, AR-Ansicht und personalisierte Barrierenbewertung unterwegs                                                     |
| **Web-Dashboard** (`dashboard/`)              | Auswertung der Feldtests im Browser – zweiter Client an derselben API                                                  |
| **Import-Pipeline** (`scripts/`)              | Python-ETL: holt Barrieren und POIs aus OSM, ginto und Wheelmap in die Datenbank                                       |

Wie die Teile zusammenhängen und welche Verträge zwischen ihnen gelten, steht
in [docs/web-architektur.md](docs/web-architektur.md).

**Bachelorarbeit** | SAE Institut Zürich | BSc Web Development  
**Studentin:** Jessica Schneiter  
**Supervisor:** Julian Heeb (ginto)  
**Zeitraum:** 21.02.2026 – 14.08.2026

## Features

- 🗺️ **Kartenansicht** – MapKit mit personalisierten Barrieren-Markern und POI-Filtern
- 📱 **AR-Ansicht** – Barrieren und zugängliche Orte als AR-Overlays im Kamerabild
- 👤 **Persönliche Barrierenlogik** – Binäre Bewertung basierend auf Rollstuhltyp, Masse und Fähigkeiten
- ♿ **5 Rollstuhltypen** – Manuell, e-motion, Joystick, Elektro, Treppensteiger (Scewo Bro)
- 📍 **Testgebiet** – Altstadt Zürich (Niederdorf/Oberdorf)

## Tech Stack

| Komponente     | Technologie                                                                          |
| -------------- | ------------------------------------------------------------------------------------ |
| iOS App        | Swift / SwiftUI                                                                      |
| AR             | ARKit + RealityKit (ARGeoTrackingConfiguration)                                      |
| Karten         | MapKit                                                                               |
| Routing        | MapKit (Fussgängerroute); Barrieren werden entlang der Route personalisiert bewertet |
| Backend        | Supabase (PostgreSQL + PostGIS), Zugriff über PostgREST, Regeln über RLS             |
| Auth           | Supabase Auth (E-Mail, Google, Apple Sign-in, anonyme Sessions für den Feldtest)     |
| Web-Dashboard  | TypeScript, Vite, Supabase JS, Vitest – ohne UI- oder Chart-Bibliothek               |
| Import-Scripts | Python (Overpass REST, ginto GraphQL)                                                |
| Datenquellen   | OSM/Overpass API, ginto API (GraphQL, ganze Schweiz), Wheelmap, OpenRouteService     |
| Design         | Figma (iPhone 17, 402×874pt); Styleguide v1.0 in Swift und CSS umgesetzt             |
| CI             | GitHub Actions (Typen, Tests und Build des Dashboards)                               |

## Projektstruktur

```
.
├── ARMikronav/                     iOS-Client (Xcode-Projekt)
│   ├── ARMikronav/
│   │   ├── ARMikronavApp.swift
│   │   ├── Config/                 AppConfig, Secrets.example.swift
│   │   ├── DesignSystem/           AppColor, AppMetrics, AppTypography, Components/
│   │   ├── Models/                 UserProfile, POI, TestProfile, BarrierFilter …
│   │   ├── Services/               BarrierLogic, RouteService, SupabaseService …
│   │   ├── ViewModels/             Onboarding, Map, HomeDashboard
│   │   ├── Views/                  AR/, Auth/, Home/, Map/, Onboarding/,
│   │   │                           Permissions/, SavedPlaces/, Settings/
│   │   ├── Support/                DistanceFormatter, AsyncRetry, AppLocale
│   │   ├── Seed/                   Offline-Startdaten (JSON)
│   │   ├── Testing/                GPX-Dateien zum Standort-Simulieren
│   │   └── Assets.xcassets/
│   ├── ARMikronavTests/            Unit-Tests (Swift Testing)
│   └── ARMikronavUITests/
├── dashboard/                      Web-Dashboard zur Feldtest-Auswertung
│   └── src/{lib,components,styles}
├── Database/schema.sql             Tabellen, Indizes, RLS
├── migrations/                     Geo-Funktionen, Feldtest-Tabellen, Seeds
├── scripts/                        Python-Import (OSM, ginto)
└── docs/web-architektur.md         Architektur und API-Verträge
```

`Barrier`, `BarrierWarning` und die Funktion `shouldWarn()` liegen zusammen in
`Services/BarrierLogic.swift` – Datentyp und Regel gehören inhaltlich zusammen
und werden nur gemeinsam geändert.

## Setup

### Voraussetzungen

- Xcode 16+ (iOS 17 SDK)
- iPhone 12+ (ARKit ARGeoTracking)
- Supabase Account
- macOS Sequoia+

Für das Web-Dashboard genügt Node 22+ – Xcode und macOS braucht es dafür nicht.

### iOS-Client

```bash
git clone https://github.com/JSss10/ar-mikronav.git
cd ar-mikronav
open ARMikronav/ARMikronav.xcodeproj
cp ARMikronav/ARMikronav/Config/Secrets.example.swift \
   ARMikronav/ARMikronav/Config/Secrets.swift
# → Supabase URL und Anon Key eintragen (Secrets.swift ist in .gitignore)
```

### Web-Dashboard

```bash
cd dashboard
npm install
cp .env.example .env     # Supabase URL und Anon Key eintragen
npm run dev              # http://localhost:5173
```

Einrichtung und Freischaltung im Detail: [dashboard/README.md](dashboard/README.md).

### Tests

```bash
# iOS: in Xcode ⌘U, oder
xcodebuild test -project ARMikronav/ARMikronav.xcodeproj -scheme ARMikronav \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Dashboard
cd dashboard && npm test
```

## Standort simulieren (Rathaus Zürich)

Zum Testen ohne vor Ort zu sein lässt sich der GPS-Standort faken –
die GPX-Datei `ARMikronav/Testing/RathausZuerich.gpx` enthält das
Rathaus Zürich (47.37172, 8.54222) als Wegpunkt.

**Simulator oder echtes iPhone (via Xcode):**

1. `RathausZuerich.gpx` per Drag & Drop ins Xcode-Projekt ziehen (einmalig).
2. App mit ▶︎ starten, dann in der Debug-Leiste unten auf das
   Pfeil-Symbol **„Simulate Location"** klicken → **RathausZuerich** wählen.
3. Alternativ als Standard setzen: **Product → Scheme → Edit Scheme… →
   Run → Options → Core Location → Default Location → RathausZuerich** –
   dann startet jeder Run direkt beim Rathaus.

**Nur Simulator (ohne GPX):** **Features → Location → Custom Location…**
und Breite `47.37172` / Länge `8.54222` eintragen.

Hinweis: Der simulierte Standort wirkt auf Karte, Suche, Routing und
Annäherungswarnungen. ARGeoTracking (AR-Modus) braucht dagegen echtes
GPS + Kamerabild vor Ort und lässt sich nicht sinnvoll simulieren.

## Feldtest-Modus (Altstadt Zürich, 3 Testtage)

Für die Feldtests wählen Testpersonen auf dem Welcome-Screen unter
**„Feldtest starten"** ihr vorgefertigtes Testprofil (Bild + Vorname,
alphabetisch sortiert, `Models/TestProfile.swift`) – keine Registrierung
nötig. Danach durchlaufen sie das normale Onboarding mit ihren eigenen
Angaben (inkl. Nachname).

**Datenerfassung (separat von den regulären App-Tabellen):**

| Tabelle             | Inhalt                                                          |
| ------------------- | --------------------------------------------------------------- |
| `test_participants` | 1 Zeile pro Testperson: Testprofil, Onboarding-Antworten (JSON) |
| `test_events`       | Alle Interaktionen: Screen-Aufrufe, Klicks, Routen, Feedback    |

**Setup vor dem ersten Testtag:**

1. `migrations/field_test_tables.sql` im Supabase SQL-Editor ausführen.
2. Supabase Dashboard → Authentication → Sign In / Providers →
   **„Allow anonymous sign-ins"** aktivieren (Testpersonen bekommen beim
   Profil-Auswählen automatisch einen anonymen User).
3. In `Config/AppConfig.swift` muss `fieldTestModeEnabled = true` stehen
   (nach den Testtagen wieder auf `false`).

**Ablauf pro Testperson:** Profil antippen → Consent → Onboarding ausfüllen →
App testen. Danach oben rechts **„Test beenden"**: lädt offene Tracking-Events
hoch und setzt das Gerät für die nächste Testperson zurück. Die
Abschluss-Umfrage wird nicht mehr in der App geöffnet — der Umfrage-Link wird
den Testpersonen separat zugestellt, damit sie ihn auf einem Tablet oder
Computer (grösser, bessere Bedienbarkeit) ausfüllen können. So lassen sich
Klickdaten (`test_events`) und Onboarding-Profil (`test_participants`) pro
Testperson zusammenführen.

## Auswertung: Web-Dashboard

Die Feldtestdaten werden im Browser ausgewertet – `dashboard/` ist ein
zweiter Client an derselben API wie die iOS-App.

Das Dashboard zeigt pro Testtag:

- **Kennzahlen** – Testpersonen, Testläufe, Ereignisse, mittlere Dauer eines
  Testlaufs, abgeschlossene Onboardings, regulär beendete Tests
- **Nutzung** – Screen-Aufrufe, Ereignisse nach Typ, Weg durch den Testlauf
  (wo brechen Testpersonen ab?), Verteilung der Rollstuhltypen
- **Testpersonen** – eine Zeile je Person mit aufklappbarem Onboarding-Profil
- **Interaktionsprotokoll** – alle Ereignisse chronologisch, filterbar
- **CSV-Export** – Testpersonen und Ereignisse für die Weiterverarbeitung

```bash
cd dashboard && npm install && npm run dev
```

Einrichtung, Freischaltung und Deployment: [dashboard/README.md](dashboard/README.md).

Wer lieber direkt abfragt, kann weiterhin den Supabase SQL-Editor benutzen:

```sql
SELECT * FROM test_event_overview WHERE test_day = '2026-07-21';
```

## Datenquellen

| Quelle           | Typ                                                                                                       | Lizenz                               |
| ---------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| OpenStreetMap    | Barrieren (kerb/sloped_curb, incline, surface, smoothness, tracktype, width, steps, sidewalk:\*, barrier) | ODbL                                 |
| OpenRouteService | Alternativroute um eine einzelne Barriere herum (Profil `wheelchair`, avoid_polygons)                     | ODbL (OSM) / ORS-Nutzungsbedingungen |
| ginto API        | POI-Zugänglichkeit (GraphQL, POIs ganze Schweiz)                                                          | Nutzungsbedingungen ginto            |
| Wheelmap         | POI wheelchair=yes/limited/no                                                                             | CC-BY-SA                             |

Die Standardroute ist die Fussgängerroute – sie nimmt den Weg, den man auch
selbst nehmen würde. Die Rollstuhl-Perspektive steckt in der personalisierten
Bewertung der Barrieren entlang dieser Route, nicht in der Geometrie: In der
Altstadt sind `width`, `surface` und `incline` an zu wenigen Gassen erfasst,
als dass ein Rollstuhl-Routing dort brauchbare Wege liefern würde (es schlug
im Feldtest weiträumige Umwege um Ziele vor, die nebenan lagen).

Welche OSM-Tags für die Barrieren ausgewertet werden und wie sie bewertet
werden, richtet sich nach dem OSM-Wiki, Projekt
[Wheelchair routing](https://wiki.openstreetmap.org/wiki/Wheelchair_routing);
die Grenzwerte nach DIN 18024-1 stehen in
`ARMikronav/Services/AccessibilityStandard.swift`.

## Tests

Getestet wird gezielt das, was rechnet und entscheidet – nicht die Oberfläche.

| Datei                                            | Prüft                                                                       |
| ------------------------------------------------ | --------------------------------------------------------------------------- |
| `ARMikronavTests/BarrierLogicTests.swift`        | `shouldWarn()`: alle Barrierenarten, Grenzwerte, Begleitung, Nässe, Energie |
| `ARMikronavTests/OSMSurfaceRatingTests.swift`    | Bewertung der OSM-Tags `surface`, `smoothness`, `tracktype`                 |
| `ARMikronavTests/RouteServiceTests.swift`        | Fortschritt entlang der Route, Fahrzeit aus eigener Geschwindigkeit         |
| `ARMikronavTests/ARHeadingCorrectionTests.swift` | Korrektur der Blickrichtung im AR-Modus                                     |
| `dashboard/src/lib/analytics.test.ts`            | Auswertungslogik: Zählungen, Dauern, Zuordnung Ereignis → Testperson        |

Die CI ([`.github/workflows/dashboard.yml`](.github/workflows/dashboard.yml))
prüft bei jeder Änderung am Dashboard Typen, Tests und Build. Die iOS-Tests
laufen lokal in Xcode – ein macOS-Runner ist dafür nicht eingerichtet.

## Commit Convention

Dieses Projekt verwendet [Conventional Commits](https://www.conventionalcommits.org/). Siehe [COMMITS.md](COMMITS.md).

## Lizenz

© 2026 Jessica Schneiter, SAE Institut Zürich. Bachelorarbeit, nicht für kommerzielle Nutzung.  
OpenStreetMap: © OpenStreetMap Contributors, ODbL | ginto: © ginto guide AG
