# Design System — Omina

Umsetzung des Styleguide v1.0 (WCAG 2.2 · Konformitätsziel AAA) im iOS-Code.
Komponenten referenzieren ausschliesslich Tokens, nie Hex-Werte direkt.

## Farbtokens (`AppColor`)

Jedes Token liegt als Colorset mit Light-/Dark-Variante in `Assets.xcassets`
(Styleguide §08). Zugriff über `AppColor.*`:

| Token (Asset)        | Light / Dark        | Verwendung                          |
| -------------------- | ------------------- | ----------------------------------- |
| `BackgroundPrimary`  | #FFFFFF / #141019   | App-Hintergrund                     |
| `SurfaceRaised`      | #FAF9FC / #1E1830   | Karten, Sheets                      |
| `TextPrimary`        | #1A1523 / #F4F1FA   | Fliesstext, Titel                   |
| `TextSecondary`      | #524A5E / #B3ACC4   | Metadaten, Hinweise                 |
| `AccentPrimary`      | #5B21B6 / #C4B5FD   | Buttons, Links, aktive Zustände     |
| `AccentPressed`      | #4C1D95 / #DDD6FE   | Gedrückte Zustände                  |
| `OnAccent`           | #FFFFFF / #2E1065   | Text auf AccentPrimary              |
| `FocusRing`          | #6D28D9 / #C4B5FD   | Fokusindikator                      |
| `ScrimAR`            | #2E1065 (beide)     | AR-Label-Hintergrund (≥ 93 %)       |
| `Status*Text/Fill/Icon` | siehe §2.3       | Barriere-Semantik (vierfach codiert)|
| `BorderFunctional`   | #8E8699 / #8A80A3   | Eingabefelder, funktionale Ränder   |
| `BorderDecorative`   | #DDD8E4 / #3D3552   | Trennlinien                         |

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
  → `.buttonStyle(.appPrimary)` / `.appSecondary` / `.appQuiet` (§4.1)
- `StatusBadge(status:)` — vierfach codiert: Farbe + Form + Symbol + Text (P2, §2.3).
  Grundformen: Kreis (zugänglich) · Dreieck (eingeschränkt) · Achteck (Barriere).

Die Status-Semantik hängt an `POIAccessStatus` (`Models/POI.swift`):
`tint`, `textColor`, `fillColor`, `symbolName`.
