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

# 3. In Supabase Table Editor prüfen:
# - barriers: sollte ~50-200 Einträge haben
# - poi_accessibility: enthält die POIs der ganzen Schweiz (ginto)
```

## Backups

Beide Scripts erstellen automatisch ein JSON-Backup mit Zeitstempel vor dem Import. Diese kannst du im Repo behalten oder als Referenz für die Thesis verwenden.
