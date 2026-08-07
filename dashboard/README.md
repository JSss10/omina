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

1. `migrations/dashboard_access.sql` im Supabase SQL-Editor ausführen.
2. Supabase Dashboard → Authentication → Users → **Add user** (E-Mail +
   Passwort). Die User-ID kopieren.
3. Im SQL-Editor freischalten:

   ```sql
   INSERT INTO dashboard_researchers (user_id, email, note)
   VALUES ('<USER-ID>', 'name@example.com', 'Auswertung Bachelorarbeit');
   ```

Ohne Schritt 3 kommt man zwar durch die Anmeldung, sieht aber keine Daten –
das Dashboard sagt das ausdrücklich, statt einen leeren Testtag zu zeigen.

## Befehle

| Befehl              | Wirkung                                     |
| ------------------- | ------------------------------------------- |
| `npm run dev`       | Entwicklungsserver mit Hot Reload           |
| `npm run typecheck` | TypeScript prüfen, ohne zu bauen            |
| `npm test`          | Tests der Auswertungslogik (Vitest)         |
| `npm run build`     | Typprüfung + Produktions-Build nach `dist/` |
| `npm run preview`   | Produktions-Build lokal ausliefern          |

## Deployment

`npm run build` erzeugt statische Dateien in `dist/` – kein Server nötig.
Bei Vercel, Netlify oder GitHub Pages als Projektverzeichnis `dashboard`,
als Build-Befehl `npm run build` und als Ausgabeverzeichnis `dist` angeben.
Die beiden `VITE_*`-Variablen müssen dort als Umgebungsvariablen hinterlegt
sein; sie werden beim Build in das Bundle eingesetzt.

> Der anon Key ist öffentlich und darf das sein. Der `service_role` Key darf
> **nie** in dieses Projekt – er umgeht RLS und läge im Browser offen.

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
│   │   ├── login.ts            Anmeldung
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
`ARMikronav/DesignSystem/{AppColor,AppMetrics,AppTypography}.swift`. Die
Hex-Werte stammen aus denselben Colorsets in `Assets.xcassets`, die Masse aus
denselben Konstanten. Wie im iOS-Code gilt: Komponenten referenzieren nur
Tokens, nie Hex-Werte.

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
