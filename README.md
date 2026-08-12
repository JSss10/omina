# Omina

> AR-gestützte Mikronavigation für Rollstuhlnutzende – iOS-Prototyp zur Entscheidungsunterstützung in barrierekritischen urbanen Situationen.

## Über das Projekt

Omina visualisiert situative Barrieren (Stufen, Steigungen, Engstellen, Oberflächen) in Echtzeit über ARKit und zeigt die Zugänglichkeit von Points of Interest im Kamerabild an. Die Barrierenbewertung ist **personalisiert** – die App warnt nur, wenn eine Barriere für das individuelle Profil der Nutzer:in nicht passierbar ist.

**Bachelorarbeit** | SAE Institut Zürich | BSc Web Development
**Studentin:** Jessica Schneiter
**Supervisor:** Julian Heeb (ginto)
**Zeitraum:** 21.02.2026 – 14.08.2026

## Features

- 🗺️ **Kartenansicht** – MapKit mit personalisierten Barrieren-Markern, POI-Filtern und Turn-by-turn-Navigation
- 📱 **AR-Ansicht** – Barrieren, Bodenpfad und zugängliche Orte als AR-Overlays im Kamerabild
- 👤 **Persönliche Barrierenlogik** – binäre Bewertung aus Rollstuhltyp, Massen, Fähigkeiten und Tagesform
- ♿ **5 Rollstuhltypen** – manuell, e-motion, Joystick, Elektro, Treppensteiger (Scewo BRO)
- 🔔 **Annäherungswarnungen** – Banner und System-Mitteilung, bevor eine kritische Barriere erreicht wird
- 🔀 **Alternativroute** – Weg um eine einzelne, heute nicht machbare Barriere herum
- 📶 **Offline-fähig** – gebündelte Seed-Daten und Datei-Cache, damit die Karte auch im Funkloch trägt
- 📍 **Testgebiet** – Altstadt Zürich (Kreis 1), POI-Daten schweizweit

## Bedienung

1. Registrieren oder mit E-Mail-Code anmelden (im Feldtest-Modus: Testprofil wählen)
2. Onboarding ausfüllen – Rollstuhltyp, Massen, Fähigkeiten, Begleitung
3. **Home** zeigt Wetter, letzte Ziele und gespeicherte Orte
4. **Karte** zeigt Orte und Barrieren in der Umgebung; ein Ort öffnet das Detail mit Zugänglichkeit, Fotos und Öffnungszeiten
5. **Route starten** – die Barrieren entlang der Strecke werden gegen das eigene Profil bewertet und aufgelistet
6. **Kamera** blendet Route und Barrieren ins Kamerabild ein

## Tech Stack

| Komponente   | Technologie                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| iOS App      | Swift 5 / SwiftUI (iOS 17+)                                                          |
| AR           | ARKit + RealityKit, Nordkorrektur über CoreMotion                                    |
| Karten       | MapKit                                                                               |
| Routing      | MapKit (Fussgängerroute); Barrieren werden entlang der Route personalisiert bewertet |
| Alternativen | OpenRouteService (Profil `wheelchair`, `avoid_polygons`)                             |
| Backend      | Supabase (PostgreSQL + PostGIS, RLS)                                                 |
| Auth         | Supabase Auth (E-Mail + Einmalcode, anonym im Feldtest)                              |
| Datenquellen | OSM/Overpass, ginto API (GraphQL), Zürich Tourismus Open Data, Wheelmap, Open-Meteo  |
| Design       | Figma (iPhone 17, 402×874 pt)                                                        |

## Architektur

```
     SwiftUI Views                ViewModels              Services / Repositories
┌────────────────────┐      ┌──────────────────┐      ┌───────────────────────────┐
│ MainTabView        │      │ MapViewModel     │      │ LocationService  (CL/CM)  │
│  ├── HomeDashboard │─────▶│ HomeDashboardVM  │─────▶│ RouteService     (MapKit) │
│  ├── MapView       │      │ OnboardingVM     │      │ BarrierRepository ─┐      │
│  ├── ARModeView    │      └──────────────────┘      │ POIRepository ─────┼─▶ Supabase
│  ├── SavedPlaces   │                                │ ProfileService     │      │
│  └── Settings      │           Models               │ AuthService  ──────┘      │
└────────────────────┘   Barrier · POI · Route        │ SeedData / LocalDataStore │
                         UserProfile · Warning        └───────────────────────────┘
                                  ▲                                 │
                                  └──── BarrierLogic.shouldWarn ◀───┘
```

Die Views halten keinen Datenzugriff: Sie lesen aus den ViewModels, diese aus den
Repositories. `BarrierLogic` ist der einzige Ort, an dem entschieden wird, ob eine
Barriere für ein Profil kritisch ist – Karte, AR-Overlay, Warnbanner, System-
Mitteilung und Routen-Liste rufen dieselbe Funktion auf und zeigen deshalb
garantiert dasselbe an.

## Getting Started

### Voraussetzungen

- Xcode 16+ (iOS 17 SDK)
- macOS Sequoia+
- iPhone 12 oder neuer (ARKit); der Simulator kann alles ausser AR
- Supabase-Projekt (PostgreSQL + PostGIS)

### Installation

```bash
git clone https://github.com/JSss10/omina.git
cd omina
cp Omina/Omina/Config/Secrets.example.swift Omina/Omina/Config/Secrets.swift
# → Supabase URL, Anon Key und (optional) OpenRouteService-Key eintragen
open Omina/Omina.xcodeproj
```

`Secrets.swift` ist per `.gitignore` ausgeschlossen und darf nie eingecheckt werden.
Die Abhängigkeit `supabase-swift` löst Xcode beim ersten Öffnen selbst auf.

### Datenbank aufsetzen

```bash
# im Supabase SQL-Editor, in dieser Reihenfolge:
supabase/schema.sql                       # Tabellen, PostGIS, RLS
supabase/migrations/*.sql                 # RPCs, Storage-Bucket, Feldtest-Tabellen
supabase/seed/seed_barriers_osm.sql       # optional: Barrieren-Grunddaten
supabase/seed/seed_pois_ginto.sql         # optional: POI-Grunddaten
```

Alternativ die Daten frisch importieren – siehe [scripts/README.md](scripts/README.md).

### Passwort zurücksetzen (Deep Link)

Der Link in der „Passwort zurücksetzen"-E-Mail führt zurück in die App und
öffnet dort den Screen **Neues Passwort**. Damit Supabase die Umleitung
zulässt, im Dashboard unter **Authentication → URL Configuration** eintragen:

| Feld          | Wert                     |
| ------------- | ------------------------ |
| Site URL      | `omina://password-reset` |
| Redirect URLs | `omina://password-reset` |

Das Schema `omina` steht in `Omina/Omina/Info.plist` (`CFBundleURLTypes`), die
Adresse selbst in `AppConfig.passwordResetRedirectURL`. Wird eines von beiden
geändert, muss der Dashboard-Eintrag mitziehen – sonst landet die Person nach
dem Klick auf einer Fehlerseite im Browser statt in der App.

**Testen:** App im Simulator starten, „Passwort vergessen" → Link senden, dann
den Link aus der E-Mail antippen. Ohne E-Mail geht es auch direkt:

```bash
xcrun simctl openurl booted "omina://password-reset"
```

Ohne gültigen Code im Link zeigt die App den Hinweis, dass er abgelaufen ist –
genau der Weg, den auch ein zweimal benutzter Link nimmt.

## Tests

```bash
xcodebuild test -scheme Omina -destination 'platform=iOS Simulator,name=iPhone 16'
```

Die Unit-Tests decken die fachlich heiklen Stellen ab – dort, wo ein Fehler zu
einer falschen Aussage über Zugänglichkeit führen würde:

| Suite                      | Prüft                                                                |
| -------------------------- | -------------------------------------------------------------------- |
| `OminaTests`               | `shouldWarn()` je Barrierentyp, Profil-Grenzwerte, Begleitungs-Bonus |
| `RouteServiceTests`        | ORS-Anfrageformat, Fortschritt, Manöver, Umweg-Plausibilität         |
| `OSMSurfaceRatingTests`    | `surface`/`smoothness`/`tracktype` gegen die Oberflächen-Toleranz    |
| `ARHeadingCorrectionTests` | Nordkorrektur der AR-Welt, wrap-sichere Winkelglättung               |
| `POIImageTests`            | Bild- und Quellenangaben aus `accessibility_details`                 |
| `POIPlaceInfoTests`        | Öffnungszeiten, Kontakt und Platzhalter im POI-Detail                |

## Standort simulieren (Rathaus Zürich)

Zum Testen ohne vor Ort zu sein lässt sich der GPS-Standort faken – die GPX-Datei
`Omina/Omina/Testing/ZurichTownHall.gpx` enthält das Rathaus Zürich
(47.37172, 8.54222) als Wegpunkt.

**Simulator oder echtes iPhone (via Xcode):**

1. `ZurichTownHall.gpx` per Drag & Drop ins Xcode-Projekt ziehen (einmalig).
2. App mit ▶︎ starten, dann in der Debug-Leiste unten auf **„Simulate Location"** → **ZurichTownHall**.
3. Alternativ als Standard setzen: **Product → Scheme → Edit Scheme… → Run → Options → Core Location → Default Location**.

**Nur Simulator (ohne GPX):** **Features → Location → Custom Location…** mit
Breite `47.37172` / Länge `8.54222`.

Der simulierte Standort wirkt auf Karte, Suche, Routing und Annäherungswarnungen.
ARGeoTracking braucht dagegen echtes GPS und Kamerabild vor Ort.

## Feldtest-Modus (Altstadt Zürich, 3 Testtage)

Testpersonen wählen auf dem Welcome-Screen unter **„Feldtest starten"** ihr
vorgefertigtes Testprofil (`Models/TestProfile.swift`) – keine Registrierung nötig.
Danach durchlaufen sie das normale Onboarding mit ihren eigenen Angaben.

**Datenerfassung** (getrennt von den regulären App-Tabellen):

| Tabelle             | Inhalt                                                          |
| ------------------- | --------------------------------------------------------------- |
| `test_participants` | 1 Zeile pro Testperson: Testprofil, Onboarding-Antworten (JSON) |
| `test_events`       | Alle Interaktionen: Screen-Aufrufe, Klicks, Routen, Feedback    |

**Setup vor dem ersten Testtag:**

1. `supabase/migrations/field_test_tables.sql` im Supabase SQL-Editor ausführen.
2. Supabase Dashboard → Authentication → Sign In / Providers → **„Allow anonymous sign-ins"** aktivieren.
3. In `Config/AppConfig.swift` muss `fieldTestModeEnabled = true` stehen (nach den Testtagen wieder auf `false`).

**Ablauf pro Testperson:** Profil antippen → Datenschutz → Zugriff erlauben → Onboarding → App testen.
Danach oben rechts **„Test beenden"**: lädt offene Tracking-Events hoch und setzt
das Gerät für die nächste Person zurück. Die Abschluss-Umfrage wird separat
zugestellt, damit sie auf einem grösseren Gerät ausgefüllt werden kann.

**Auswertung** im Supabase SQL-Editor, z. B.:

```sql
SELECT * FROM test_event_overview WHERE test_day = '2026-07-21';
```

## Projektstruktur

```
omina/
├── Omina/                          # Xcode-Projekt
│   ├── Omina/
│   │   ├── OminaApp.swift          # App-Einstieg, Routing nach Auth-State
│   │   ├── Config/                 # AppConfig (öffentlich), Secrets (ignoriert)
│   │   ├── Models/                 # Barrier, POI, Route, UserProfile, …
│   │   ├── Services/               # Repositories, Routing, AR, Standort, Auth
│   │   ├── ViewModels/             # MapViewModel, HomeDashboardVM, OnboardingVM
│   │   ├── Views/                  # Root · Auth · Onboarding · Home · Map · AR · …
│   │   ├── DesignSystem/           # Farben, Typografie, Masse, Komponenten
│   │   ├── Support/                # Formatierer, Retry, Locale, Extensions
│   │   ├── Seed/                   # Offline-Grunddaten (Bundle)
│   │   └── Testing/                # GPX-Standorte für Xcode
│   ├── OminaTests/                 # Unit-Tests
│   └── OminaUITests/               # UI-Tests
├── dashboard/                      # Web-Auswertung der Feldtage (Vite + TS)
│   ├── src/lib/                    # Supabase-Zugriff, Auswertungslogik, CSV
│   ├── src/components/             # KPIs, Diagramme, Testpersonen, Protokoll
│   └── src/styles/                 # Design-Tokens, portiert aus dem iOS-Styleguide
├── supabase/
│   ├── schema.sql                  # Tabellen, PostGIS, RLS
│   ├── migrations/                 # RPCs, Storage-Bucket, Feldtest-Tabellen,
│   │                               # Leserecht fürs Dashboard
│   └── seed/                       # Grunddaten als SQL-Dump
├── scripts/                        # Python-Importe (OSM, ginto, Zürich Tourismus)
├── data/exports/                   # Je Import-Script der massgebliche Lauf
│                                   # (Beleg für die Arbeit); das Ergebnis von
│                                   # import_osm.py ist der Seed selbst
├── COMMITS.md                      # Commit- und Branch-Konvention
├── THIRD-PARTY-NOTICES.md          # Fremdkomponenten und Datenlizenzen
└── LICENSE                         # proprietär, alle Rechte vorbehalten
```

## Datenquellen

| Quelle           | Typ                                                                                                       | Lizenz                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| OpenStreetMap    | Barrieren (kerb/sloped_curb, incline, surface, smoothness, tracktype, width, steps, sidewalk:\*, barrier) | ODbL                                       |
| OpenRouteService | Alternativroute um eine einzelne Barriere (Profil `wheelchair`, avoid_polygons)                           | ODbL (OSM) / ORS-Nutzungsbedingungen       |
| ginto API        | POI-Zugänglichkeit (GraphQL, POIs ganze Schweiz)                                                          | Nutzungsbedingungen ginto                  |
| Zürich Tourismus | POI-Fotos, Öffnungszeiten, Kontakt (Open Data 2.0, `/en/api/v2/data`)                                     | Open Data Zürich Tourismus, Quellennennung |
| Wheelmap         | POI wheelchair=yes/limited/no                                                                             | CC BY-SA                                   |
| Open-Meteo       | Wetter für die Tagesform-Anpassung                                                                        | CC BY 4.0                                  |

Die Standardroute ist die Fussgängerroute – sie nimmt den Weg, den man auch selbst
nehmen würde. Die Rollstuhl-Perspektive steckt in der personalisierten Bewertung
der Barrieren entlang dieser Route, nicht in der Geometrie: In der Altstadt sind
`width`, `surface` und `incline` an zu wenigen Gassen erfasst, als dass ein
Rollstuhl-Routing dort brauchbare Wege liefern würde (es schlug im Feldtest
weiträumige Umwege um Ziele vor, die nebenan lagen).

Fotos, Öffnungszeiten und Kontaktangaben im POI-Detail kommen aus dem Open-Data-API
von Zürich Tourismus (Version 2.0). `scripts/import_zurich_tourism.py` prüft jeden
ginto-POI gegen dieses API – zugeordnet wird über Distanz und Namensähnlichkeit –
und schreibt die Treffer nach `accessibility_details`. Kennt das API einen Ort
nicht, zeigt das Detail-Sheet Platzhalter statt leerer Flächen. Die Quellenangabe
steht unter den Fotos und den übernommenen Angaben; die Lizenz verlangt die Nennung.

Welche OSM-Tags für die Barrieren ausgewertet und wie sie bewertet werden, richtet
sich nach dem OSM-Wiki, Projekt _Wheelchair routing_; die Grenzwerte nach
DIN 18024-1 stehen in `Omina/Omina/Services/AccessibilityStandard.swift`.

## Commit Convention

Dieses Projekt verwendet [Conventional Commits](https://www.conventionalcommits.org/).
Siehe [COMMITS.md](COMMITS.md).

## Tools

Claude, Version Opus 5, Anthropic: https://claude.ai – Unterstützung bei Code-Review, Refactoring, Teststruktur und Textstruktur der Dokumentation.

Figma, Figma Inc.: https://www.figma.com – Screen-Design, Design-Tokens und Prototyp (iPhone 17, 402×874 pt).

DeepL Translate, DeepL SE: https://www.deepl.com/de/translator – Übersetzung einzelner Textpassagen.

## Lizenz

© 2026 Jessica Schneiter. Alle Rechte vorbehalten – **keine Open-Source-Lizenz**.
Das Repository ist öffentlich einsehbar, damit die Bachelorarbeit nachvollziehbar
bleibt; eine Nutzung, Vervielfältigung oder Weiterverbreitung des Codes ist damit
nicht gestattet. Die vollständigen Bedingungen stehen in [LICENSE](LICENSE),
die Fremdkomponenten und Datenlizenzen in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Datennachweis: OpenStreetMap © OpenStreetMap-Mitwirkende (ODbL) | ginto © ginto guide AG |
Fotos und Ortsangaben © Zürich Tourismus (zuerich.com) | Wetter © Open-Meteo (CC BY 4.0)

## Sources

Aufgeführt sind die Quellen, auf die dieses Repository unmittelbar aufbaut –
Normen, Schnittstellen-Dokumentationen und Datenquellen, die im Code, in den
Import-Scripts oder im Design-System referenziert werden. Die Literatur der
schriftlichen Arbeit steht dort in eigenem Verzeichnis.

Apple Inc., 2026a. _ARKit | Apple Developer Documentation_. [online] Verfügbar unter: https://developer.apple.com/documentation/arkit [Zugegriffen 12. April 2026].

Apple Inc., 2026b. _Core Motion | Apple Developer Documentation_. [online] Verfügbar unter: https://developer.apple.com/documentation/coremotion [Zugegriffen 24. Juli 2026].

Apple Inc., 2026c. _MapKit for SwiftUI | Apple Developer Documentation_. [online] Verfügbar unter: https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui [Zugegriffen 20. Juli 2026].

Apple Inc., 2026d. _Licensed Application End User License Agreement_. [online] Verfügbar unter: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ [Zugegriffen 26. Juli 2026].

Deutsches Institut für Normung, 1998. _DIN 18024-1: Barrierefreies Bauen – Teil 1: Strassen, Plätze, Wege, öffentliche Verkehrs- und Grünanlagen sowie Spielplätze; Planungsgrundlagen_. Berlin: Beuth Verlag.

ginto guide AG, 2026. _ginto – Zugänglichkeit finden_. [online] Verfügbar unter: https://ginto.guide [Zugegriffen 28. März 2026].

HeiGIT gGmbH, 2026. _openrouteservice API Documentation – Directions Service_. [online] Verfügbar unter: https://openrouteservice.org/dev/#/api-docs/v2/directions [Zugegriffen 18. Juni 2026].

Open-Meteo, 2026. _Free Weather API_. [online] Verfügbar unter: https://open-meteo.com/ [Zugegriffen 14. Juli 2026].

OpenStreetMap Foundation, 2026. _Copyright and Licence_. [online] Verfügbar unter: https://www.openstreetmap.org/copyright [Zugegriffen 7. April 2026].

OpenStreetMap Wiki, 2026a. _Wheelchair routing_. [online] Verfügbar unter: https://wiki.openstreetmap.org/wiki/Wheelchair_routing [Zugegriffen 7. April 2026].

OpenStreetMap Wiki, 2026b. _Overpass API_. [online] Verfügbar unter: https://wiki.openstreetmap.org/wiki/Overpass_API [Zugegriffen 7. April 2026].

Preston-Werner, T. und Mitwirkende, 2019. _Conventional Commits 1.0.0_. [online] Verfügbar unter: https://www.conventionalcommits.org/de/v1.0.0/ [Zugegriffen 28. März 2026].

Schema.org Community Group, 2026. _Schema.org Vocabulary_. [online] Verfügbar unter: https://schema.org/ [Zugegriffen 9. August 2026].

Supabase Inc., 2026. _Supabase Documentation_. [online] Verfügbar unter: https://supabase.com/docs [Zugegriffen 28. März 2026].

W3C, 2023. _Web Content Accessibility Guidelines (WCAG) 2.2_. [online] W3C Recommendation. Verfügbar unter: https://www.w3.org/TR/WCAG22/ [Zugegriffen 15. Mai 2026].

Wheelmap.org, 2026. _Wheelmap – Rollstuhlgerechte Orte finden_. [online] Verfügbar unter: https://wheelmap.org/ [Zugegriffen 10. April 2026].

Zürich Tourismus, 2026. _Open Data Version 2.0_. [online] Verfügbar unter: https://www.zuerich.com/en/open-data-version-20 [Zugegriffen 9. August 2026].
