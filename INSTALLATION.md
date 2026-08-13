# Installation und Bewertung

Anleitung für die Prüfung dieser Arbeit. Es gibt drei Wege, die Arbeit
anzuschauen – vom schnellsten zum vollständigsten. Für die reine Bewertung
genügen die ersten beiden; der dritte zeigt, dass das Projekt aus dem
Quellcode heraus baut.

Die Zugangsdaten (Keys, Logins) stehen **nicht in diesem Repository**, sondern
in der Datei `ZUGANGSDATEN.md` im Abgabeordner. Dieses Dokument sagt nur,
welcher Wert wohin gehört.

| Weg                         | Aufwand | Braucht           | Zeigt                     |
| --------------------------- | ------- | ----------------- | ------------------------- |
| 1 · TestFlight              | 2 Min   | iPhone (iOS 17+)  | die fertige App, inkl. AR |
| 2 · Dashboard im Browser    | 1 Min   | Browser + Login   | die Feldtest-Auswertung   |
| 3 · Aus dem Quellcode bauen | 20 Min  | Mac mit Xcode 16+ | Build, Tests, Architektur |

---

## Weg 1 · Die App über TestFlight (empfohlen)

Der einzige Weg, auf dem der AR-Modus wirklich läuft – ARKit braucht Kamera
und Bewegungssensoren, der Simulator kann das nicht.

1. Auf dem iPhone **TestFlight** aus dem App Store installieren.
2. Den TestFlight-Link aus `ZUGANGSDATEN.md` auf dem iPhone öffnen.
3. **Accept** → **Install** → Omina startet wie eine normale App.
4. Anmelden mit dem Testkonto aus `ZUGANGSDATEN.md` (oder selbst
   registrieren – der Bestätigungscode kommt per E-Mail).

**Voraussetzungen:** iPhone 12 oder neuer (ARKit), iOS 17 oder neuer.
Die App fragt nach Standort und Kamera; beides ist für Karte, Navigation und
AR-Ansicht nötig.

**Ohne Zürich vor Ort:** Karte, Suche, POI-Details, Routenberechnung und
Barrierenbewertung funktionieren überall. Für die AR-Ansicht mit echten
Barrieren muss man in der Altstadt Zürich (Kreis 1) stehen – dort liegen die
erfassten Daten. Wer den Standort simulieren will, findet die Anleitung im
[README](README.md#standort-simulieren-rathaus-zürich).

---

## Weg 2 · Das Auswertungs-Dashboard im Browser

Die Weboberfläche zu den drei Feldtesttagen: Kennzahlen, Nutzungsverteilung,
Testpersonen-Profile und das vollständige Interaktionsprotokoll.

1. Die Dashboard-URL aus `ZUGANGSDATEN.md` im Browser öffnen.
2. Mit dem dort angegebenen Konto anmelden (E-Mail + Passwort).

Es gibt bewusst keine Registrierung: Wer Daten sehen darf, entscheidet die
Tabelle `dashboard_researchers` in der Datenbank – das regelt Row Level
Security, nicht der Schlüssel im Browser. Ein Konto ohne diesen Eintrag kommt
zwar durch die Anmeldung, sieht aber ausdrücklich «Dieses Konto ist nicht
freigeschaltet» statt eines leeren Testtags.

Hintergrund und Aufbau: [dashboard/README.md](dashboard/README.md).

---

## Weg 3 · Aus dem Quellcode bauen

### 3.1 Voraussetzungen

- macOS Sequoia oder neuer
- Xcode 16+ (iOS 17 SDK)
- Node.js 20+ (nur für das Dashboard)
- iPhone 12 oder neuer für den AR-Modus; der Simulator kann alles ausser AR

### 3.2 iOS-App

```bash
git clone https://github.com/JSss10/omina.git
cd omina
cp Omina/Omina/Config/Secrets.example.swift Omina/Omina/Config/Secrets.swift
```

Jetzt `Secrets.swift` öffnen und die vier Werte aus `ZUGANGSDATEN.md`
eintragen. Im Abgabeordner liegt unter `konfiguration/Secrets.swift` eine
bereits ausgefüllte Fassung – die lässt sich direkt an diese Stelle kopieren:

```bash
cp <Abgabeordner>/konfiguration/Secrets.swift Omina/Omina/Config/Secrets.swift
```

Wichtig: Die Vorlage `Secrets.example.swift` steht in einem `#if false`-Block,
damit sie nicht mitkompiliert. Beim Ausfüllen der echten Datei muss dieser
Block weg – die ausgefüllte Fassung im Abgabeordner hat ihn bereits nicht.

```bash
open Omina/Omina.xcodeproj
```

Xcode löst die Abhängigkeit `supabase-swift` beim ersten Öffnen selbst über
den Swift Package Manager auf (einmalig, braucht Internet). Danach:
Schema **Omina** wählen, Ziel **iPhone 16 Simulator** oder ein angeschlossenes
Gerät, **▶︎**.

Für den Build auf echter Hardware braucht es in Xcode unter
**Signing & Capabilities** ein eigenes Entwicklerteam – die Bundle-ID muss
dabei angepasst werden. Wer das umgehen will, nimmt Weg 1 (TestFlight).

`Secrets.swift` ist per `.gitignore` ausgeschlossen und steht deshalb nicht
im Repository. Das ist Absicht, kein fehlender Teil der Abgabe.

### 3.3 Tests

```bash
xcodebuild test -scheme Omina -destination 'platform=iOS Simulator,name=iPhone 16'
```

Welche Suite was prüft, steht im [README](README.md#tests). Die Tests laufen
ohne Netz und ohne gültige Keys – sie prüfen die Bewertungslogik, nicht die
Anbindung.

### 3.4 Dashboard lokal

```bash
cd dashboard
npm install
cp .env.example .env      # Werte aus ZUGANGSDATEN.md eintragen
npm run dev               # http://localhost:5173
```

Auch hier liegt im Abgabeordner unter `konfiguration/dashboard.env` eine
ausgefüllte Fassung; sie wird als `dashboard/.env` abgelegt:

```bash
cp <Abgabeordner>/konfiguration/dashboard.env dashboard/.env
```

Weitere Befehle (`npm test`, `npm run build`, `npm run typecheck`):
[dashboard/README.md](dashboard/README.md#befehle).

---

## Die Datenbank

Das Supabase-Projekt läuft bereits – App, Dashboard und die veröffentlichte
Vercel-Seite hängen alle daran. **Für die Bewertung muss nichts aufgesetzt
werden.**

Wer die Datenbank trotzdem von Grund auf nachbauen will (eigenes
Supabase-Projekt, dann eigene URL und eigener anon Key in den Konfigurationen),
führt im SQL-Editor in dieser Reihenfolge aus:

```
supabase/schema.sql                       Tabellen, PostGIS, RLS
supabase/migrations/*.sql                 RPCs, Storage-Bucket, Feldtest-Tabellen,
                                          Leserecht fürs Dashboard
supabase/seed/seed_barriers_osm.sql       Barrieren-Grunddaten
supabase/seed/seed_pois_ginto.sql         POI-Grunddaten
```

Die Grunddaten frisch importieren statt einspielen: [scripts/README.md](scripts/README.md).

---

## Welcher Wert gehört wohin

Alle konkreten Werte stehen in `ZUGANGSDATEN.md` im Abgabeordner.

| Wert                 | Datei                              | Schlüssel                |
| -------------------- | ---------------------------------- | ------------------------ |
| Supabase URL         | `Omina/Omina/Config/Secrets.swift` | `supabaseURL`            |
| Supabase anon Key    | `Omina/Omina/Config/Secrets.swift` | `supabaseAnonKey`        |
| ginto API Key        | `Omina/Omina/Config/Secrets.swift` | `gintoAPIKey`            |
| OpenRouteService Key | `Omina/Omina/Config/Secrets.swift` | `openRouteServiceAPIKey` |
| Supabase URL         | `dashboard/.env`                   | `VITE_SUPABASE_URL`      |
| Supabase anon Key    | `dashboard/.env`                   | `VITE_SUPABASE_ANON_KEY` |

Zwei Hinweise dazu:

- Der **anon Key** ist öffentlich gedacht. Er identifiziert das Projekt, nicht
  die Person, und gibt für sich genommen nichts frei – der Zugriff hängt am
  angemeldeten Konto und an Row Level Security. In das Browser-Bundle des
  Dashboards wird er ohnehin einkompiliert.
- Der **ginto-Token** und der **OpenRouteService-Key** sind dagegen echte
  Geheimnisse und stehen deshalb nur im Abgabeordner, nie im öffentlichen
  Repository.

Ohne OpenRouteService-Key läuft die App weiter: Die Navigation fällt dann auf
die MapKit-Fussgängerroute zurück, nur die Alternativroute um eine einzelne
Barriere herum fehlt. Ohne ginto-Token laufen App und Dashboard vollständig –
der Token wird allein vom Import-Script `scripts/import_ginto.py` gebraucht,
die App liest POIs ausschliesslich über Supabase.

---

## Bekannte Einschränkungen

- **AR nur auf echter Hardware.** Der Simulator hat keine Kamera und keine
  Bewegungssensoren; die AR-Ansicht bleibt dort leer. Alles andere – Karte,
  Suche, POI-Details, Routing, Barrierenbewertung, Warnungen – funktioniert
  im Simulator.
- **Daten nur für die Altstadt Zürich.** Barrieren sind für den Stadtkreis 1
  erfasst (POI-Daten schweizweit). Ausserhalb zeigt die Karte korrekterweise
  nichts an.
- **Feldtest-Modus ist aus.** `AppConfig.fieldTestModeEnabled` steht auf
  `false` – so, wie die App nach den drei Testtagen laufen soll. Wer den
  Ablauf der Testtage sehen will (Testprofil-Auswahl statt Registrierung),
  setzt das Flag in `Omina/Omina/Config/AppConfig.swift` auf `true` und baut
  neu; dafür muss in Supabase zusätzlich «Allow anonymous sign-ins» aktiv
  sein. Die _Ergebnisse_ der Testtage sind ohne diesen Schritt im Dashboard
  sichtbar.

---

## Übersicht der Adressen

| Was                   | Adresse                         |
| --------------------- | ------------------------------- |
| Quellcode             | https://github.com/JSss10/omina |
| App (TestFlight)      | Link in `ZUGANGSDATEN.md`       |
| Auswertungs-Dashboard | https://omina-nav.vercel.app/   |
| Datenschutzerklärung  | https://jsss10.github.io/omina/ |

---

**Bachelorarbeit** | SAE Institut Zürich | BSc Web Development
Jessica Schneiter · Supervisor: Julian Heeb (ginto) · 21.02.2026 – 14.08.2026
