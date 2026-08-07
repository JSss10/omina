# Architektur

Wie das System aufgebaut ist, welche Verträge zwischen den Teilen gelten und
warum es so geschnitten ist. Gedacht als Vorlage für das Architekturkapitel
der Arbeit.

## 1. Überblick

Das System ist eine Client-Server-Anwendung mit zwei Clients an einer
gemeinsamen HTTP-API. Die Datenschicht ist die einzige Stelle, an der Daten
liegen; beide Clients sehen dieselben Tabellen durch dieselben Regeln.

```
      ┌──────────────────────┐        ┌──────────────────────┐
      │  iOS-Client          │        │  Web-Dashboard       │
      │  Swift / SwiftUI     │        │  TypeScript / Vite   │
      │  ARKit · MapKit      │        │  Browser             │
      └──────────┬───────────┘        └──────────┬───────────┘
                 │  HTTPS · JSON · JWT           │
                 │                               │
                 └───────────────┬───────────────┘
                                 ▼
              ┌────────────────────────────────────────┐
              │  API-Schicht (PostgREST auf Supabase)  │
              │  Tabellen-Endpunkte · RPC-Funktionen   │
              │  Auth (JWT) · Row Level Security       │
              └───────────────────┬────────────────────┘
                                  ▼
              ┌────────────────────────────────────────┐
              │  PostgreSQL 15 + PostGIS               │
              │  barriers · poi_accessibility ·        │
              │  saved_places · user_feedback ·        │
              │  test_participants · test_events       │
              └───────────────────▲────────────────────┘
                                  │  Python-ETL (einmalig je Import)
              ┌───────────────────┴────────────────────┐
              │  Overpass API (REST) · ginto (GraphQL) │
              └────────────────────────────────────────┘
```

Vier Teile, vier Verantwortlichkeiten:

| Teil            | Verzeichnis                | Verantwortung                                             |
| --------------- | -------------------------- | --------------------------------------------------------- |
| Datenschicht    | `Database/`, `migrations/` | Datenmodell, Geo-Abfragen, Zugriffsregeln                 |
| iOS-Client      | `ARMikronav/`              | Navigation unterwegs, AR, personalisierte Bewertung       |
| Web-Dashboard   | `dashboard/`               | Auswertung der Feldtests                                  |
| Import-Pipeline | `scripts/`                 | Externe Datenquellen in das eigene Datenmodell überführen |

## 2. Warum zwei Clients

Die beiden Clients lösen verschiedene Aufgaben unter verschiedenen
Bedingungen, und diese Bedingungen bestimmen die Technik:

**Unterwegs** braucht es die Kamera für die AR-Ansicht, das Magnetometer für
die Blickrichtung, hochfrequentes GPS und Betrieb bei wackligem Netz. Das ist
nativ zu lösen; ARKits `ARGeoTrackingConfiguration` hat im Web keine
Entsprechung.

**Bei der Auswertung** braucht es das Gegenteil: einen grossen Bildschirm,
Tabellen, Export, Zugriff von jedem Gerät ohne Installation und ohne
Verteilung über TestFlight. Das ist im Browser zu lösen.

Dieselbe Datenschicht bedient beide. Der Schnitt zwischen Client und Server
verläuft nicht zwischen App und Dashboard, sondern zwischen Darstellung und
Daten – und er hält, weil ein zweiter, technisch völlig anderer Client an
derselben API tatsächlich funktioniert. Das ist der praktische Nachweis, dass
die Trennung sauber ist und keine Server-Logik in den iOS-Client gerutscht ist.

## 3. Die API

### 3.1 Tabellen-Endpunkte

PostgREST bildet jede Tabelle auf einen REST-Endpunkt ab. Der iOS-Client
schreibt darüber Feedback und Tracking-Ereignisse, das Dashboard liest die
Feldtestdaten.

| Endpunkt                     | Methode       | Client    | Zweck                                    |
| ---------------------------- | ------------- | --------- | ---------------------------------------- |
| `/rest/v1/test_participants` | POST (upsert) | iOS       | Testperson mit Onboarding-Profil anlegen |
| `/rest/v1/test_participants` | GET           | Dashboard | Testpersonen eines Testtags              |
| `/rest/v1/test_events`       | POST          | iOS       | Interaktions-Ereignisse (gebündelt)      |
| `/rest/v1/test_events`       | GET           | Dashboard | Ereignisse zur Auswertung                |
| `/rest/v1/user_feedback`     | POST          | iOS       | Korrekturmeldung zu einer Barriere       |
| `/rest/v1/saved_places`      | POST/DELETE   | iOS       | Ort merken / entfernen                   |

### 3.2 RPC-Funktionen als eigene Endpunkte

Wo eine Tabellenabfrage nicht reicht, liegen eigene Funktionen in der
Datenbank. Sie sind der eigentliche Anwendungsvertrag: benannte Operationen
mit festen Parametern und einem festen Rückgabeschema.

| Funktion                                              | Parameter                         | Liefert                                                     |
| ----------------------------------------------------- | --------------------------------- | ----------------------------------------------------------- |
| `barriers_within_radius(lat, lng, radius_meters)`     | Punkt und Radius in Metern        | Aktive Barrieren im Umkreis, nach Distanz sortiert          |
| `pois_within_radius(lat, lng, radius_meters, search)` | zusätzlich Suchbegriff            | POIs im Umkreis, gefiltert über Name/Kategorie, mit Distanz |
| `saved_places_list()`                                 | keine – arbeitet auf `auth.uid()` | Gespeicherte Orte des angemeldeten Kontos                   |
| `field_test_days()`                                   | keine                             | Testtage mit Anzahl Testpersonen                            |

Drei Entwurfsentscheide, die in diesen Funktionen stecken:

**Die Geo-Abfrage gehört an die Daten, nicht in den Client.** `ST_DWithin`
nutzt den GIST-Index auf `location`; über die Leitung geht nur, was der
Client wirklich anzeigt. Die Alternative – alle Barrieren laden und im Client
filtern – wäre auf Mobilfunk unbrauchbar.

**Das Rückgabeschema ist auf die Clients zugeschnitten.** PostGIS-`geography`
serialisiert PostgREST standardmässig als WKB-Hex. Die Funktionen geben
stattdessen `latitude` und `longitude` als `double precision` zurück
(`ST_Y`/`ST_X`), damit weder Swift noch TypeScript einen WKB-Parser braucht.
Der Vertrag richtet sich nach dem, was die Aufrufenden verarbeiten können.

**`search_path` ist fixiert.** Jede Funktion setzt
`SET search_path = public, extensions, pg_temp`. Ohne das könnte eine
gleichnamige Tabelle in einem anderen Schema untergeschoben werden – bei
`SECURITY DEFINER`-Funktionen eine Rechteausweitung. Der Supabase-Linter
prüft genau das (`function_search_path_mutable`).

### 3.3 Authentifizierung

Supabase Auth stellt nach der Anmeldung ein JWT aus, das beide Clients bei
jeder Anfrage als `Authorization: Bearer` mitschicken. Aus dem Token liest
PostgreSQL `auth.uid()` – dieselbe ID, auf die sich die Zugriffsregeln
beziehen.

Drei Wege hinein, je nach Situation:

| Weg                                      | Wer                      | Warum                                                                                                     |
| ---------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------- |
| E-Mail + Passwort, OAuth (Google, Apple) | Reguläre Nutzende        | Konto über Geräte hinweg                                                                                  |
| Anonyme Sitzung                          | Testpersonen im Feldtest | Kein Registrieren am Testtag – aber jede Person bekommt eine eigene ID, an der die Zugriffsregeln greifen |
| E-Mail + Passwort                        | Auswertung im Dashboard  | Ein Konto, das zusätzlich freigeschaltet sein muss                                                        |

## 4. Zugriffsregeln (Row Level Security)

Der Zugriff hängt am angemeldeten Konto, nicht am API-Schlüssel. Jede Tabelle
hat RLS aktiviert; PostgreSQL hängt die Bedingung an jede Abfrage an,
unabhängig davon, welcher Client sie stellt.

| Tabelle                                       | Lesen                                             | Schreiben            |
| --------------------------------------------- | ------------------------------------------------- | -------------------- |
| `barriers`, `poi_accessibility`, `test_areas` | alle (öffentliche Kartendaten)                    | niemand über die API |
| `saved_places`, `user_feedback`               | nur eigene Zeilen (`auth.uid() = user_id`)        | nur eigene Zeilen    |
| `test_participants`, `test_events`            | eigene Zeilen **oder** freigeschaltete Auswertung | nur eigene Zeilen    |
| `dashboard_researchers`                       | nur der eigene Eintrag                            | niemand über die API |

Die Freischaltung der Auswertung ist die interessante Stelle
(`migrations/dashboard_access.sql`):

```sql
CREATE POLICY "test_events_select_researcher" ON test_events
    FOR SELECT USING (is_dashboard_researcher());
```

Drei Punkte dazu:

1. **Additiv statt ersetzend.** PostgreSQL verknüpft mehrere PERMISSIVE
   Policies mit ODER. Die bestehende Regel für Testpersonen bleibt gültig; die
   neue kommt daneben. Es musste nichts an `field_test_tables.sql` geändert
   werden.
2. **`SECURITY DEFINER` gegen Rekursion.** `is_dashboard_researcher()` fragt
   `dashboard_researchers` ab. Liefe diese Abfrage ihrerseits durch die RLS
   derselben Tabelle, entstünde eine Endlosschleife. `SECURITY DEFINER` mit
   fixiertem `search_path` löst das.
3. **Nur Lesen.** Für die Auswertung gibt es bewusst keine INSERT/UPDATE/
   DELETE-Policy. Ein Auswertungswerkzeug darf die Rohdaten eines Feldtests
   nicht verändern können – auch nicht versehentlich.

### Warum kein `service_role` Key im Dashboard

Der naheliegende Weg wäre gewesen, das Dashboard mit dem `service_role` Key zu
betreiben, der RLS umgeht. Das Dashboard läuft aber im Browser: alles, was in
das Bundle kompiliert wird, ist öffentlich. Der Schlüssel läge in den
DevTools offen, und wer die Seite aufruft, hätte Vollzugriff auf alle Daten
der Testpersonen.

Das Dashboard benutzt deshalb denselben öffentlichen anon Key wie die App.
Öffentlich ist er unbedenklich, weil er für sich genommen nichts freigibt –
er identifiziert das Projekt, nicht die Person. Die Berechtigung entsteht
erst durch Anmeldung plus Eintrag in `dashboard_researchers`.

## 5. Datenfluss

### 5.1 Import (einmalig je Datenquelle)

`scripts/import_osm.py` fragt die Overpass API nach den Tags, die das
OSM-Wiki für Rollstuhl-Routing auflistet, übersetzt sie in das eigene
Barrieren-Modell und schreibt sie in `barriers`. `scripts/import_ginto.py`
holt POI-Bewertungen über GraphQL mit Paginierung.

Zwei Dinge sind hier bewusst gelöst:

- **Herkunft bleibt sichtbar.** `value_source` unterscheidet `measured`
  (Wert stand im Tag) von `estimated` (Wert aus einem Default-Mapping nach
  DIN 18024-1). Die Bewertung im Client behandelt beide unterschiedlich –
  siehe 5.3.
- **Vor jedem Schreiben ein Backup.** Die Scripts legen ein JSON mit
  Zeitstempel an, bevor sie in die Datenbank schreiben.

### 5.2 Erfassung im Feldtest

Der iOS-Client sammelt Interaktionen lokal und lädt sie gebündelt hoch
(`TestAnalyticsService`): 2 Sekunden Sammelphase, damit schnell
aufeinanderfolgende Klicks in einem Request landen. Schlägt der Upload fehl,
bleiben die Ereignisse in den UserDefaults und werden beim nächsten Ereignis
oder App-Start nachgereicht.

Das ist die Antwort auf die Bedingung vor Ort: In den Gassen der Altstadt
bricht das Mobilfunknetz regelmässig weg. Ohne Puffer wären genau die
Ereignisse verloren, die an den interessanten Stellen entstehen.

### 5.3 Bewertung im Client

Die personalisierte Bewertung (`shouldWarn()` in `Services/BarrierLogic.swift`)
läuft bewusst im Client, nicht auf dem Server:

- Sie muss im AR-Modus mehrmals pro Sekunde auf neue Positionsdaten reagieren –
  ein Netzaufruf je Barriere käme zu spät.
- Sie muss offline funktionieren.
- Das Profil ist die persönlichste Angabe im System (Körpermasse, Fähigkeiten,
  Tagesform). Es bleibt auf dem Gerät; der Server sieht Barrieren und Profil
  nie zusammen.

Die Regel selbst ist knapp und für jede Barrierenart explizit. Ein Detail
verdient im Kapitel eine eigene Erwähnung – der Umgang mit Unsicherheit
(NFA-15):

```swift
case .incline:
    guard let incline = barrier.value else { return true }
    if barrier.valueSource == .estimated {
        return incline >= profile.effectiveMaxIncline   // im Zweifel warnen
    }
    return incline > profile.effectiveMaxIncline
```

Ein geschätzter Wert genau auf dem Limit warnt, ein gemessener nicht. Fehlt
der Wert ganz, wird gewarnt. Die Fehlerrichtung ist bewusst gewählt: eine
überflüssige Warnung kostet Zeit, eine fehlende schickt jemanden in ein
Hindernis. `ARMikronavTests/BarrierLogicTests.swift` prüft genau diese
Grenzfälle.

### 5.4 Auswertung im Dashboard

Das Dashboard lädt Testpersonen und Ereignisse und aggregiert im Browser
(`src/lib/analytics.ts`): Kennzahlen, Screen-Häufigkeiten, Dauer je Testlauf,
Weg durch den Testlauf. Die Aggregation ist als reine Funktionen ohne DOM und
ohne Netzwerk geschrieben und in `analytics.test.ts` getestet – Fehler dort
wären in den Ergebnissen nicht als Fehler erkennbar, sie sähen aus wie
Messwerte.

Ereignisse werden seitenweise geladen (`range()`), weil PostgREST je Anfrage
höchstens 1000 Zeilen liefert und ein Testtag darüber liegen kann.

## 6. Gemeinsames Design System

Der Styleguide v1.0 ist zweimal umgesetzt, aus einer Quelle:

| Ebene       | iOS                                         | Web                             |
| ----------- | ------------------------------------------- | ------------------------------- |
| Farben      | `AppColor` → Colorsets in `Assets.xcassets` | `tokens.css`, gleiche Hex-Werte |
| Typografie  | `AppTypography` → SF Pro, Dynamic Type      | `--font-*`, System-Font-Stack   |
| Masse       | `AppMetrics` → Points                       | `--space-*`, `--touch-*` in px  |
| Komponenten | `PrimaryButtonStyle` usw.                   | `.btn--primary` usw.            |

In beiden gilt dieselbe Regel: Komponenten referenzieren nur Tokens, nie
Hex-Werte. Eine Farbänderung im Styleguide ist damit an zwei Stellen
nachzuziehen – und nur an zweien.

Eine Stelle weicht ab, mit Grund: `QuietButtonStyle` setzt auf iOS fix
Violett 100 als Fläche. Im Web bekommt der Dark Mode dafür eine eigene Stufe
(`--quiet-fill`), weil `AccentPrimary` dort aufhellt und die Kombination sonst
unter das Kontrastminimum fiele. Dokumentiert im Kommentar in `tokens.css`.

## 7. Barrierefreiheit im Dashboard

Konformitätsziel wie in der App: WCAG 2.2, Ziel AAA. Bei einer Arbeit über
Barrierefreiheit muss das Werkzeug zur Auswertung denselben Massstab erfüllen
wie der Gegenstand der Untersuchung.

| Kriterium                       | Umsetzung                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------------ |
| 1.4.6 Kontrast (erweitert, AAA) | Text ab 7:1 – die Tokens bringen die geprüften Werte mit                                         |
| 1.4.8 Darstellung (AAA)         | Zeilenhöhe 1,5; Zeilenlänge auf 80 Zeichen begrenzt                                              |
| 2.4.13 Fokusdarstellung (AAA)   | 3-px-Ring mit 3 px Abstand, Teil jeder Komponente                                                |
| 2.5.5 Zeigergrösse (AAA)        | Touch-Ziele ab 44 px, Primäraktionen 56 px                                                       |
| 2.3.3 Animation (AAA)           | `prefers-reduced-motion` schaltet Übergänge ab                                                   |
| 1.4.1 Ohne Farbe                | Status vierfach codiert: Farbe + Form + Symbol + Text                                            |
| 1.1.1 Nicht-Text-Inhalt         | Diagramme sind keine Bilder: Wert und Beschriftung stehen als Text, der Balken ist `aria-hidden` |
| 2.4.1 Blöcke umgehen            | Sprungmarke zum Hauptinhalt                                                                      |
| 1.4.10 Reflow                   | Breite Tabellen scrollen im eigenen Container, nie die Seite                                     |
| 1.4.4 Textgrösse                | Keine feste `font-size` am `html`-Element; alle Grössen in `rem`                                 |

Der letzte Punkt in der Tabelle – Diagramme ohne Bild – ist der Grund, warum
keine Chart-Bibliothek verwendet wird: die meisten erzeugen ein SVG oder
Canvas, für das eine Textalternative nachgereicht werden muss. Ein
Balkendiagramm aus DOM-Elementen braucht keine, weil die Daten selbst der
Inhalt sind.

## 8. Sicherheit

| Thema             | Umsetzung                                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Zugriffskontrolle | RLS auf jeder Tabelle; Berechtigung am Konto, nicht am Schlüssel                                                                  |
| Schlüssel         | Nur anon Key in beiden Clients; `service_role` ausschliesslich in den Import-Scripts, dort aus Umgebungsvariablen                 |
| Secrets           | `Secrets.swift` und `.env` in `.gitignore`, Vorlagen als `*.example` eingecheckt                                                  |
| XSS               | Alle Inhalte als Textknoten (`src/lib/dom.ts`), kein `innerHTML` – Namen und Freitexte aus dem Feldtest können kein Markup werden |
| Rechteausweitung  | Fixierter `search_path` in allen SQL-Funktionen                                                                                   |
| Datensparsamkeit  | Profil bleibt für die Bewertung auf dem Gerät; Feldtestdaten liegen getrennt von den regulären App-Tabellen                       |
| Indexierung       | `noindex, nofollow` im Dashboard – die Seite zeigt Daten von Testpersonen                                                         |

## 9. Qualitätssicherung

| Ebene     | Werkzeug                    | Umfang                                                       |
| --------- | --------------------------- | ------------------------------------------------------------ |
| iOS       | Swift Testing               | Barrierenlogik, OSM-Bewertung, Routenfortschritt, AR-Heading |
| Dashboard | Vitest                      | Auswertungslogik                                             |
| Typen     | TypeScript strict           | `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`     |
| CI        | GitHub Actions              | Typen, Tests und Build des Dashboards bei jeder Änderung     |
| Feldtest  | 3 Testtage, Altstadt Zürich | Reale Nutzung mit Rollstuhlnutzenden                         |

Getestet wird, was rechnet und entscheidet – nicht die Oberfläche. Die
Oberfläche wurde im Feldtest mit echten Nutzenden geprüft; das ist die
belastbarere Aussage über sie.

## 10. Bekannte Grenzen

- **Kein macOS-Runner in der CI.** Die iOS-Tests laufen lokal in Xcode. Die
  CI deckt nur das Dashboard ab.
- **Die Barrierenlogik existiert nur in Swift.** Sollte das Dashboard einmal
  dieselbe Bewertung zeigen wollen, müsste sie entweder als Edge Function
  (TypeScript) dupliziert oder in die Datenbank verlagert werden. Für den
  Umfang dieser Arbeit war die Duplikation das grössere Risiko.
- **Keine Live-Aktualisierung.** Das Dashboard lädt auf Anforderung neu.
  Supabase Realtime wäre über denselben Kanal möglich, war für die Auswertung
  nach den Testtagen aber nicht nötig.
- **Rollstuhl-Routing statt Fussgänger-Routing** liefert in der Altstadt
  keine brauchbaren Wege, weil `width`, `surface` und `incline` dort an zu
  wenigen Gassen erfasst sind. Die Rollstuhl-Perspektive steckt deshalb in der
  Bewertung der Barrieren entlang der Route, nicht in der Geometrie.
