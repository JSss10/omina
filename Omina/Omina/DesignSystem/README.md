# Design System — Omina

Umsetzung des Styleguide v1.0 (WCAG 2.2 · Konformitätsziel AAA) im iOS-Code.
Komponenten referenzieren ausschliesslich Tokens, nie Hex-Werte direkt.

## Farbtokens (`AppColor`)

Jedes Token liegt als Colorset mit Light-/Dark-Variante in `Assets.xcassets`
(Styleguide §08). Zugriff über `AppColor.*`:

| Token (Asset)           | Light / Dark      | Verwendung                           |
| ----------------------- | ----------------- | ------------------------------------ |
| `BackgroundPrimary`     | #FFFFFF / #141019 | App-Hintergrund                      |
| `BackgroundMuted`       | #EDE9FE / #1E1830 | Zustands-Screens, Medien-Platzhalter |
| `SurfaceRaised`         | #FAF9FC / #1E1830 | Karten, Sheets                       |
| `SurfaceTinted`         | #F5F3FF / #241D3A | Getönte Karten in den Sheets         |
| `TextPrimary`           | #1A1523 / #F4F1FA | Fliesstext, Titel                    |
| `TextSecondary`         | #524A5E / #B3ACC4 | Metadaten, Hinweise                  |
| `TextBrand`             | #2E1065 / #DDD6FE | Marken-Überschriften (Splash, Intro) |
| `AccentPrimary`         | #5B21B6 / #C4B5FD | Buttons, Links, aktive Zustände      |
| `AccentPressed`         | #4C1D95 / #DDD6FE | Gedrückte Zustände                   |
| `OnAccent`              | #FFFFFF / #2E1065 | Text auf AccentPrimary               |
| `AccentMuted`           | #C4B5FD / #4C1D95 | Inaktive Primäraktion (Entwurf)      |
| `FocusRing`             | #6D28D9 / #C4B5FD | Fokusindikator                       |
| `ScrimAR`               | #2E1065 (beide)   | AR-Label-Hintergrund (≥ 93 %)        |
| `Status*Text/Fill/Icon` | siehe §2.3        | Barriere-Semantik (vierfach codiert) |
| `BorderFunctional`      | #8E8699 / #8A80A3 | Eingabefelder, funktionale Ränder    |
| `BorderDecorative`      | #DDD8E4 / #3D3552 | Trennlinien                          |

`AppColor.Violet.v50…v950` stellt zusätzlich die volle Violett-Palette (§2.1) bereit.

`AccentColor` (Asset) ist auf AccentPrimary gesetzt, damit bestehende
`.accentColor`/`.tint`-Aufrufe automatisch die Leitfarbe übernehmen.

## Typografie (`AppTypography`)

SF Pro über die SwiftUI-Text-Styles → Dynamic Type bis AX5 (§03).
`AppTypography.largeTitle … footnote`, plus `Text.bodyStyle()` (Zeilenhöhe 1,5).

## Masse (`AppMetrics`)

- `Touch.minimum` 44 · `Touch.primary` 56 · `Touch.arCritical` 72 (§6.1, WCAG 2.5.5)
- `Radius`, `Space` (4-pt-Raster), `Focus` (3-pt-Ring), `AR` (Scrim/Label-Regeln)

## Komponenten

- `PrimaryButtonStyle` / `SecondaryButtonStyle` / `QuietButtonStyle`
  → `.buttonStyle(.appPrimary)` / `.appSecondary` / `.appQuiet` (§4.1).
  Inaktiv steht die Primäraktion gedämpft in `AccentMuted` mit dunkler Schrift,
  statt auszugrauen; die Sekundäraktion trägt den Umriss in `TextBrand`.
- `NavigationActionLabel(title:direction:)` — Beschriftung mit Richtungspfeil
  («‹ Zurück», «Weiter ›») für die Fusszeilen von Registrierung und Onboarding.
- `AppTextField(placeholder:text:…)` — Eingabefeld nach Entwurf: Beschriftung
  im Feld statt als Label-Zeile, optionale Auge-Schaltfläche fürs Passwort.
  `.appFieldChrome()` / `.compactFieldChrome()` geben zusammengesetzten Feldern
  (Vorwahl + Nummer, Zahlenfelder in Karten) dieselbe Fläche.
- `SelectionRow(label:icon:selected:)` und `SelectionMark(selected:)` — getönte
  Auswahlzeile mit gepunktetem Ring (offen) bzw. gefülltem Häkchen (gewählt).
- `InfoCard(icon:title:detail:)` — Hinweiskarte mit Symbol im hellvioletten
  Kreis (Handy-Ausrichtung, Datenschutz, Zugriff erlauben).
- `BrandAccentBar()` — die violette Leiste unter der Statusleiste auf allen
  Screens ohne Navigationsleiste. Fortschritt zeigt stattdessen
  `OnboardingProgressBar`.
- `AuthHeader(title:subtitle:)` — Titel im Markenviolett mit erklärender Zeile,
  Abstände nach Entwurf (Willkommen, Anmelden, Registrieren, Passwort,
  Datenschutz, Zugriff erlauben).
- `PasswordStrengthBar(strength:)` mit `PasswordStrength.evaluate(_:)` — fünf
  Segmente plus Stufe als Wort, damit die Bewertung nicht nur über Farbe und
  Menge codiert ist.
- `SearchBar(placeholder:…)`, `FilterIconButton(activeCount:…)` und
  `CategoryPill(label:symbol:isSelected:)` — die Bedienzeile aus Suche, Filter
  (mit Plakette für die Zahl gesetzter Filter) und Kategorie-Chips; gleich auf
  Homescreen, Karte und im Such-Sheet.
- `OminaTabBar(items:selection:)` — schwebende violette Navigationsleiste;
  der aktive Eintrag sitzt im weissen Kreis. Ersetzt die System-Tab-Leiste
  optisch, die Auswahl läuft weiter über dieselbe Bindung.
- `SheetHeader`, `SheetSection`, `SheetRowIcon`, `SheetToggleRow` — Kopfzeile,
  Abschnitt und Zeilen der Karten-Sheets (Filter, Routen, Suche).
- `StatusBadge(status:)` — vierfach codiert: Farbe + Form + Symbol + Text (P2, §2.3).
  Grundformen: Kreis (zugänglich) · Dreieck (eingeschränkt) · Achteck (Barriere).

Die Status-Semantik hängt an `POIAccessStatus` (`Models/POI.swift`):
`tint`, `textColor`, `fillColor`, `symbolName`.
