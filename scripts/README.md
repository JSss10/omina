# Import Scripts

Python-Scripts zum Importieren von Daten in die Supabase-Datenbank.

## Setup

```bash
# 1. Python Dependencies installieren
pip3 install requests supabase

# 2. Environment Variablen setzen
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_SERVICE_KEY="YOUR_SERVICE_ROLE_KEY"
export GINTO_API_KEY="YOUR_GINTO_BEARER_TOKEN"
```

⚠️ **Service Role Key (nicht anon Key!)** – findest du in Supabase unter Settings → API → "service_role" secret. Diesen Key NIE im Frontend verwenden!

## Scripts

### import_osm.py

Lädt Barrieren-Daten aus OpenStreetMap (Overpass API) für die Altstadt Zürich und schreibt sie in die `barriers` Tabelle.

```bash
python3 import_osm.py
```

Ausgewertet werden die Tags, die das OSM-Wiki im Projekt
[Wheelchair routing](https://wiki.openstreetmap.org/wiki/Wheelchair_routing)
auflistet – dieselben Tags, auf denen auch das Rollstuhl-Routing der App
(OpenRouteService, Profil `wheelchair`) rechnet.

**Was wird importiert:**

| OSM-Tag                                    | Barriere in der App              |
| ------------------------------------------ | -------------------------------- | ------------------- | ---------------------------------- |
| `kerb` (+ `kerb:height`)                   | Bordstein, sonst Default-Mapping |
| `sloped_curb`, `sloped_curb:start`/`:end`  | Bordstein am Weganfang/-ende     |
| `highway=steps` (+ `step_count`)           | Treppe                           |
| `incline` (% oder °, sonst Default 8 %)    | Steigung                         |
| `surface` (Kopfsteinpflaster, Kies, Sand…) | Oberfläche                       |
| `smoothness` (ab `intermediate`)           | Oberfläche (Ebenheit)            |
| `tracktype` (ab `grade2`)                  | Oberfläche (Wegequalität)        |
| `width` (< 200 cm)                         | Engstelle                        |
| `sidewalk:left                             | right                            | both:<eigenschaft>` | dieselben Typen, seitlich versetzt |
| `highway=crossing` + `wheelchair=no`       | fehlende Bordstein-Absenkung     |
| `barrier=*` (Drehkreuz, Poller, Tor…)      | Engstelle bzw. Bordstein         |

Gehweg-Tags hängen in OSM an der Strassenachse, gefahren wird aber auf dem
Trottoir – sie werden deshalb 4 m quer zur Digitalisierrichtung versetzt
(`left`/`right` beziehen sich laut Wiki genau darauf).

**value_source:**

- `measured`: Wert direkt aus OSM-Tag
- `estimated`: Wert aus Default-Mapping (NFA-15: eher warnen). Die
  Schätzwerte folgen DIN 18024-1, wie sie das Wiki zusammenfasst
  (Bordstein max. 3 cm, Nebenweg min. 90 cm, Längsneigung 3 % bzw. 6 % mit
  Verweilplätzen) – dieselben Zahlen stehen in der App unter
  `Services/AccessibilityStandard.swift`.

### import_ginto.py

Lädt alle verfügbaren POIs aus der ginto GraphQL API für die **ganze Schweiz** (Suchmittelpunkt Älggi-Alp, Radius 300 km, mit Paginierung) und schreibt sie in die `poi_accessibility` Tabelle. Holt die Bewertungen für 3 Rollstuhltypen (Handrollstuhl, E-Rollstuhl, Scewo BRO).

```bash
python3 import_ginto.py
```

**Was wird importiert:**

- Name, Adresse, Koordinaten
- Kategorie (Café, Restaurant, WC, etc.)
- Zugänglichkeit pro Rollstuhltyp:
  - Handrollstuhl (manual)
  - E-Rollstuhl (power)
  - Scewo BRO (scewo)
- grade (COMPLETELY/PARTIALLY/BADLY) + conformance (0-100%)

### import_zuerich.py

Prüft für **jeden** bestehenden POI, ob es ihn im
[Open-Data-API von Zürich Tourismus](https://www.zuerich.com/en/open-data-version-20)
(Version 2.0) gibt, und übernimmt bei einem Treffer Fotos, Öffnungszeiten,
Telefon, Webseite und Kurzbeschreibung. Die ginto-Daten haben nichts davon –
dieses Script schliesst die Lücke für Stadt und Region Zürich. POIs ohne
Treffer bleiben unverändert; die App zeigt dort Platzhalter.

```bash
python3 import_zuerich.py --dry-run   # erst die Zuordnung ansehen
python3 import_zuerich.py             # dann schreiben (fragt nach)
```

**Wie das API aufgebaut ist** (nur unter `/en/` verfügbar, kein API-Key nötig):

| Aufruf                        | Ergebnis                                      |
| ----------------------------- | --------------------------------------------- |
| `GET /en/api/v2/data`         | Liste aller Kategorien (`id`, `name`, `path`) |
| `GET /en/api/v2/data?id=<id>` | Alle Einträge einer Kategorie                 |

Die Einträge sind nach Schema.org aufgebaut, mehrsprachige Felder kommen als
Objekt (`{"de": …, "en": …}`). Die Bilder stecken in `image` (Hauptbild) und
`photo` (weitere Bilder), die Position in `geoCoordinates`, die Zeiten in
`openingHours` (Freitext) bzw. `openingHoursSpecification` (strukturiert).

**Zuordnung API-Eintrag → POI:** über die Distanz **und** die
Namensähnlichkeit – beides zusammen, weil in der Altstadt viele Lokale dicht
beieinanderliegen und Namen sich wiederholen.

- ≤ 150 m und ≥ 86 % Namensähnlichkeit, oder
- ≤ 40 m und ≥ 70 % (gleiches Gebäude, leicht abweichender Name)

Verglichen wird der normalisierte Name (ohne Akzente/Satzzeichen) und der
Kern-Name ohne generische Wörter, damit «Marktgasse Hotel» und «Hotel
Marktgasse» zusammenfinden.

**Was geschrieben wird** – ausschliesslich in `accessibility_details`, und nur
die Felder, die das API tatsächlich liefert:

| Feld                 | Inhalt                                                                    |
| -------------------- | ------------------------------------------------------------------------- |
| `images`             | Liste `{url, caption, credit}` (max. 5, Hauptbild zuerst)                 |
| `image_source`       | `Zürich Tourismus (zuerich.com)` für den Bildnachweis                     |
| `opening_hours`      | Anzeigezeilen, z. B. `["Mo-Fr 09:00-18:00", "Sa 10:00-16:00"]`            |
| `opening_hours_spec` | strukturiert `[{days: [1…7], opens, closes}]`, 1 = Montag                 |
| `phone`, `email`     | Kontakt                                                                   |
| `website`            | Webseite des Ortes (die zuerich.com-Seite steht separat in `zuerich_url`) |
| `description`        | Kurzbeschreibung, HTML entfernt, auf 500 Zeichen gekürzt                  |
| `price_range`        | Preisniveau                                                               |
| `zuerich_name`       | gefundener Name im API – macht die Zuordnung nachvollziehbar              |
| `info_source`        | Quellenangabe für die Textangaben                                         |

Genau diese Schlüssel liest `POI.swift`. Das Detail-Sheet zeigt daraus das
Foto-Karussell, eine Öffnungszeiten-Karte mit hervorgehobenem heutigem Tag
(dafür `opening_hours_spec`), Telefon- und Webseiten-Zeile sowie die
Quellenangabe – deren Nennung verlangt die Lizenz von Zürich Tourismus.
Fehlt ein Feld, zeigt die App an dieser Stelle einen Platzhalter.

Zum Schluss gibt das Script aus, wie viele POIs das API kennt und welche
Felder es beisteuert – diese Abdeckung gehört in die Arbeit:

```
OK 128 von 439 POIs im API gefunden (29 %)
   mit Fotos             121
   mit Oeffnungszeiten    94
   ...
   ohne Treffer          311 (die App zeigt dort Platzhalter)
```

**Optionen:**

| Option                | Zweck                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------- |
| `--dry-run`           | nur Zuordnung zeigen, nichts schreiben                                                 |
| `--pois-file <json>`  | POIs aus einem Import-Backup lesen (Vorschau ganz ohne Supabase)                       |
| `--seed-file <json>`  | zusätzlich `Omina/Omina/Seed/seed_pois.json` pflegen (Offline-Daten der App) |
| `--categories 72,101` | nur bestimmte Kategorien abfragen (72 = Sehenswürdigkeiten, 101 = Gastronomie)         |
| `--radius-km`         | Umkreis um Zürich, in dem POIs geprüft werden (Standard 25)                            |
| `--max-distance-m`    | maximale Distanz für einen Treffer (Standard 150)                                      |
| `--max-images`        | höchstens so viele Bilder je POI (Standard 5)                                          |
| `--yes`               | ohne Rückfrage schreiben                                                               |

Neben dem Backup-JSON schreibt das Script ein idempotentes
`poi_zuerich_<zeitstempel>.sql`. Damit lassen sich die Angaben auch ohne
Service-Key über den Supabase-SQL-Editor einspielen (die UPDATEs mergen per
`||` in das bestehende JSONB, alles andere bleibt stehen).

## Workflow

```bash
# 1. OSM Daten importieren
python3 import_osm.py
# → fragt nach Bestätigung vor dem Schreiben in Supabase
# → erstellt Backup-JSON

# 2. ginto POIs importieren
python3 import_ginto.py
# → fragt nach Bestätigung vor dem Schreiben in Supabase
# → erstellt Backup-JSON

# 3. POIs gegen Zürich Tourismus prüfen und ergänzen (nach dem ginto-Import)
python3 import_zuerich.py --seed-file ../Omina/Omina/Seed/seed_pois.json
# → fragt nach Bestätigung vor dem Schreiben in Supabase
# → erstellt Backup-JSON und ein SQL-Script
# → hält die Offline-Daten der App auf demselben Stand

# 4. In Supabase Table Editor prüfen:
# - barriers: sollte ~50-200 Einträge haben
# - poi_accessibility: enthält die POIs der ganzen Schweiz (ginto)
# - accessibility_details: bei den Zürcher POIs mit Treffer um images,
#   opening_hours, phone, website ... ergänzt
```

## Backups

Beide Scripts erstellen automatisch ein JSON-Backup mit Zeitstempel vor dem Import. Diese kannst du im Repo behalten oder als Referenz für die Thesis verwenden.
