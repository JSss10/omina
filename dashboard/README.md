# Feldtest-Dashboard

Web-Auswertung der Feldtests zur AR-Mikronavigation. Liest die Tabellen
`test_participants` und `test_events` aus Supabase und zeigt Kennzahlen,
Nutzungsverteilungen, Testpersonen-Profile und das Interaktionsprotokoll.

Zweiter Client an derselben API wie die iOS-App: gleiche Datenbank, gleiche
Row-Level-Security, gleiches Design System – nur im Browser statt auf dem
iPhone.

## Tech Stack

| Bereich     | Technologie                                            |
| ----------- | ------------------------------------------------------ |
| Sprache     | TypeScript (strict, `noUncheckedIndexedAccess`)        |
| Build       | Vite                                                   |
| Daten       | Supabase JS (PostgREST + Auth)                         |
| Darstellung | Eigene DOM-Komponenten, keine UI-Bibliothek            |
| Diagramme   | Selbst gebaut aus DOM und CSS, keine Chart-Bibliothek  |
| Tests       | Vitest                                                 |
| Design      | CSS Custom Properties, portiert aus dem iOS-Styleguide |

Laufzeit-Abhängigkeit ist einzig `@supabase/supabase-js` – alles Weitere
steckt im Projekt selbst.

## Setup

```bash
cd dashboard
npm install
cp .env.example .env    # Supabase URL und anon Key eintragen
npm run dev             # http://localhost:5173
```

### Zugang freischalten

Das Dashboard meldet sich mit einem echten Supabase-Konto an; welche Zeilen
sichtbar sind, entscheidet Row Level Security. Einmalig einzurichten:

1. `supabase/migrations/dashboard_access.sql` im Supabase SQL-Editor ausführen.
2. Supabase Dashboard → Authentication → Users → **Add user** (E-Mail +
   Passwort). Die User-ID kopieren.
3. Im SQL-Editor freischalten:

   ```sql
   INSERT INTO dashboard_researchers (user_id, email, note)
   VALUES ('<USER-ID>', 'name@example.com', 'Auswertung Bachelorarbeit');
   ```

Ohne Schritt 3 kommt man zwar durch die Anmeldung, sieht aber keine Daten –
das Dashboard sagt das ausdrücklich, statt einen leeren Testtag zu zeigen.

### Konto aus der App

App und Dashboard hängen an derselben Supabase-Instanz und damit an
derselben Benutzertabelle (`auth.users`). Ein Konto aus der App kommt
deshalb mit E-Mail und Passwort auch hier durch die Anmeldung – ein zweites
Konto braucht es nicht. Was es sieht, ist damit aber nicht entschieden:
Ohne Eintrag in `dashboard_researchers` greift die RLS und das Dashboard
zeigt «Dieses Konto ist nicht freigeschaltet».

Umgekehrt gilt dasselbe: Das Auswertungskonto kann sich in der App
anmelden, ist dort aber eine gewöhnliche Nutzerin ohne Sonderrechte. Die
Rolle hängt an der Tabelle, nicht am Konto selbst.

Zwei Unterschiede zur App bleiben:

- Das Dashboard kennt nur die Anmeldung mit Passwort. Ein Konto, das in der
  App ausschliesslich über den Einmalcode angelegt wurde und gar kein
  Passwort hat, kommt hier nicht hinein – für solche Konten im Supabase
  Dashboard unter Authentication → Users ein Passwort setzen.
- Registrieren kann man sich hier nicht. Konten legt die Betreuung im
  Supabase-Dashboard an.

## Befehle

| Befehl              | Wirkung                                     |
| ------------------- | ------------------------------------------- |
| `npm run dev`       | Entwicklungsserver mit Hot Reload           |
| `npm run typecheck` | TypeScript prüfen, ohne zu bauen            |
| `npm test`          | Tests der Auswertungslogik (Vitest)         |
| `npm run build`     | Typprüfung + Produktions-Build nach `dist/` |
| `npm run preview`   | Produktions-Build lokal ausliefern          |

## Deployment auf Vercel

`npm run build` erzeugt statische Dateien in `dist/` – es läuft kein Server,
nur ausgelieferte Dateien. `vercel.json` bringt Framework-Erkennung,
Build-Befehl und die Sicherheits-Header mit; einzustellen sind nur das
Projektverzeichnis und die beiden Umgebungsvariablen.

1. [vercel.com/new](https://vercel.com/new) → GitHub-Repository `ar-mikronav`
   importieren.
2. **Root Directory** auf `dashboard` setzen. Das ist der einzige Schritt,
   den Vercel nicht erraten kann – ohne ihn sucht es im Repo-Wurzelverzeichnis
   und findet keine `package.json`. Framework (Vite), Build-Befehl
   (`npm run build`) und Ausgabeverzeichnis (`dist`) kommen aus `vercel.json`.
3. **Environment Variables** hinterlegen, für alle drei Umgebungen
   (Production, Preview, Development):

   | Name                     | Wert                            |
   | ------------------------ | ------------------------------- |
   | `VITE_SUPABASE_URL`      | `https://<projekt>.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | der **anon public** Key         |

4. **Deploy**. Jeder Push auf den Branch löst danach ein neues Deployment aus.
5. In Supabase unter **Authentication → URL Configuration** die
   Vercel-Domain zu den **Redirect URLs** hinzufügen.

> `VITE_*`-Variablen werden beim Build in das Bundle eingesetzt und sind
> im Browser lesbar. Der anon Key darf das sein – er identifiziert das
> Projekt, nicht die Person, und gibt für sich genommen nichts frei. Der
> `service_role` Key darf **nie** hierhin: er umgeht RLS und läge offen.

### Sicherheits-Header

`vercel.json` setzt sie für alle Antworten:

| Header                    | Zweck                                                                             |
| ------------------------- | --------------------------------------------------------------------------------- |
| `Content-Security-Policy` | Skripte und Styles nur aus eigener Herkunft, Netzwerkverbindungen nur zu Supabase |
| `X-Robots-Tag`            | Die Seite zeigt Daten von Testpersonen und gehört nicht in Suchmaschinen          |
| `X-Frame-Options`         | Kein Einbetten in fremde Seiten (Clickjacking)                                    |
| `X-Content-Type-Options`  | Kein Erraten des Inhaltstyps                                                      |
| `Referrer-Policy`         | Keine URL-Weitergabe an Dritte                                                    |
| `Permissions-Policy`      | Kamera, Mikrofon und Standort abgeschaltet                                        |

Die CSP enthält `style-src 'unsafe-inline'`, weil die Balkenbreite der
Diagramme als `style`-Attribut gesetzt wird. Skripte bleiben auf `'self'`
beschränkt – dort wäre `'unsafe-inline'` die riskante Freigabe, nicht bei
Styles.

### Andere Anbieter

Netlify oder GitHub Pages funktionieren genauso: Basisverzeichnis
`dashboard`, Build `npm run build`, Ausgabe `dist`. `vercel.json` wird dort
nicht gelesen – die Header müssten als `netlify.toml` bzw. über einen
vorgelagerten Dienst gesetzt werden.

## Aufbau

```
dashboard/
├── index.html
├── src/
│   ├── main.ts                 Einstieg: Konfiguration, Sitzung, Ansicht
│   ├── app.ts                  Zustand und Aufbau des Dashboards
│   ├── lib/
│   │   ├── supabase.ts         Client (anon Key)
│   │   ├── data.ts             Abfragen inkl. Paginierung
│   │   ├── analytics.ts        Auswertung – reine Funktionen
│   │   ├── analytics.test.ts   Tests dazu
│   │   ├── types.ts            Zeilentypen der Tabellen
│   │   ├── format.ts           Beschriftungen und Formatierung (de-CH)
│   │   ├── csv.ts              Export nach RFC 4180
│   │   └── dom.ts              DOM-Helfer ohne innerHTML
│   ├── components/
│   │   ├── chrome.ts           Akzentleiste und Titelblock der Screens
│   │   ├── login.ts            Anmeldung
│   │   ├── icons.ts            Auge und Warndreieck als Inline-SVG
│   │   ├── theme.ts            Hell/Dunkel/System
│   │   ├── kpi.ts              Kennzahlen-Kacheln
│   │   ├── chart.ts            Balkendiagramm
│   │   ├── participants.ts     Testpersonen-Tabelle
│   │   └── eventLog.ts         Interaktionsprotokoll
│   └── styles/
│       ├── tokens.css          Design-Tokens aus dem iOS-Styleguide
│       └── app.css             Komponenten und Layout
└── .env.example
```

## Design System

`src/styles/tokens.css` ist die Web-Portierung von
`Omina/Omina/DesignSystem/{AppColor,AppMetrics,AppTypography}.swift`. Die
Hex-Werte stammen aus denselben Colorsets in `Assets.xcassets`, die Masse aus
denselben Konstanten. Wie im iOS-Code gilt: Komponenten referenzieren nur
Tokens, nie Hex-Werte.

Nicht nur die Tokens sind portiert, sondern auch die Bausteine aus
`DesignSystem/Components`. Das Dashboard sieht deshalb aus wie die App und
nicht wie ein Verwaltungswerkzeug:

| Web (`app.css`)      | App                                   | Merkmal                                                                |
| -------------------- | ------------------------------------- | ---------------------------------------------------------------------- |
| `.brand-bar`         | `BrandAccentBar.swift`                | violette Leiste über jedem Screen                                      |
| `.auth-header`       | `AuthHeader.swift`                    | Grosstitel im Markenviolett mit erklärender Zeile                      |
| `.input` / `.select` | `AppTextField.swift`                  | getönte Fläche ohne Rand, Beschriftung im Feld, Auge am Passwort       |
| `.btn--*`            | `AppButtonStyles.swift`               | 56 px hoch, Radius 14; inaktiv gedämpft statt ausgegraut               |
| `.card` / `.table`   | `SheetChrome.swift`                   | getönte Karten, violette Abschnittstitel, feine Trennlinien            |
| `.btn--compact`      | `SearchChrome.swift` (`CategoryPill`) | Kapseln für kompakte Aktionen                                          |
| `.tabbar`            | `OminaTabBar.swift`                   | schwebende violette Kapsel; der aktive Eintrag sitzt auf heller Fläche |
| `.state`             | `AppStateScreen.swift`                | getönter Zustands-Screen mit Titel im Markenviolett                    |

Die Flächen tragen die Gliederung, nicht Rahmen und Schatten: Karten,
Felder und Chips stehen violett getönt auf hellem Grund – und dort, wo sie
selbst auf einer getönten Karte sitzen, kehrt sich das Verhältnis um
(helle Fläche auf getöntem Grund), wie in `CompactFieldChrome`.

Die Navigationskapsel führt zu den vier Abschnitten der Seite. Welcher
Abschnitt gerade oben steht, ermittelt ein `IntersectionObserver`; fehlt er,
bleibt die Hervorhebung stehen und die Sprungmarken funktionieren weiter.
Symbole gibt es nur zwei (Auge, Warndreieck) – SF Symbols stehen im Browser
nicht zur Verfügung, und beide Stellen tragen ihre Aussage ohnehin als Text.

### Responsive Verhalten

Ein einziges Layout von 320 px bis 1920 px, ohne separate mobile Variante.
Die Spaltenzahl ergibt sich aus dem verfügbaren Platz
(`repeat(auto-fit, minmax(min(100%, …), 1fr))`), nicht aus Geräteklassen:

| Viewport   | KPI-Kacheln | Diagramme |
| ---------- | ----------- | --------- |
| 320–375 px | 1 Spalte    | 1 Spalte  |
| 600 px     | 2 Spalten   | 1 Spalte  |
| 768 px     | 2 Spalten   | 2 Spalten |
| 1024 px    | 3 Spalten   | 2 Spalten |
| 1440 px    | 5 Spalten   | 4 Spalten |

Das `min(100%, …)` im `minmax()` ist der entscheidende Teil: ohne ihn
erzwingt die Mindestspaltenbreite bei schmalen Viewports horizontales
Scrollen der ganzen Seite. Breite Tabellen scrollen in ihrem eigenen
Container (`.table-scroll`) – die Seite selbst nie. Geprüft bei 320, 375,
390, 600, 768, 1024, 1440 und 1920 px sowie bei 200 % und 400 % Zoom.

Konformitätsziel wie in der App – WCAG 2.2, Ziel AAA:

- Kontraste ab 7:1 für Fliesstext (die Tokens bringen die Werte mit)
- Fokusindikator 3 px mit 3 px Abstand (2.4.13), Teil jeder Komponente
- Touch-Ziele ab 44 px, Primäraktionen 56 px (2.5.5)
- Zeilenhöhe 1,5 und maximal 80 Zeichen Zeilenlänge (1.4.8)
- Status vierfach codiert: Farbe + Form + Symbol + Text (1.4.1)
- Sprungmarke zum Inhalt (2.4.1), `prefers-reduced-motion` respektiert (2.3.3)
- Dark Mode über Systemeinstellung oder Umschalter, nie reines Schwarz

Diagramme sind keine Bilder: Beschriftung und Wert stehen als Text im DOM,
der Balken ist `aria-hidden`. Damit braucht es keine Textalternative, und
die Aussage hängt nicht an der Farbe.

## Sicherheit

- Nur der öffentliche anon Key im Bundle; der Zugriff hängt am angemeldeten
  Konto, nicht am Schlüssel.
- Alle Inhalte werden als Textknoten gesetzt (`src/lib/dom.ts`), nie über
  `innerHTML`. Namen und Freitexte aus dem Feldtest können damit kein Markup
  werden.
- `noindex, nofollow` im `<head>` – die Seite enthält Daten von Testpersonen
  und gehört nicht in Suchmaschinen.
