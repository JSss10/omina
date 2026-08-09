#!/usr/bin/env python3
"""
Zuerich-Tourismus Bilder-Import - AR-Mikronavigation

Holt die Fotos aus dem Open-Data-API von Zuerich Tourismus (Version 2.0,
https://www.zuerich.com/en/open-data-version-20) und haengt sie an die
bestehenden POIs in der Supabase-Tabelle poi_accessibility an. Die POIs
selbst stammen aus ginto/OSM und haben keine Bilder - das API von
Zuerich Tourismus liefert die passenden, hochwertigen Aufnahmen dazu.

API-Aufbau (Version 2.0, nur unter /en/ verfuegbar):

    GET /en/api/v2/data              Liste aller Kategorien
                                     [{id, name, path, parent}, ...]
    GET /en/api/v2/data?id=<id>      Alle Eintraege einer Kategorie

Die Eintraege sind nach Schema.org aufgebaut; mehrsprachige Felder kommen
als Objekt {"de": ..., "en": ...}. Die Bilder stecken in `image`
(Hauptbild) und `photo` (weitere Bilder), die Position in `geoCoordinates`.

Zuordnung API-Eintrag -> POI: ueber die Distanz (Standard 150 m) UND die
Namensaehnlichkeit. Beides zusammen, weil in der Altstadt viele Lokale
dicht beieinanderliegen und Namen wie "Hotel Storchen" mehrfach vorkommen.

Geschrieben wird ausschliesslich in accessibility_details:

    images        Liste {url, caption, credit} - genau das Format, das
                  POI.swift (POIImage) liest
    image_source  "Zuerich Tourismus (zuerich.com)" fuer den Bildnachweis

Verwendung:
    python3 import_zuerich_images.py                  # Supabase lesen + schreiben
    python3 import_zuerich_images.py --dry-run        # nur Vorschau
    python3 import_zuerich_images.py --pois-file ../pois_ginto_20260407_142744.json
                                                      # Vorschau ohne Supabase

Voraussetzungen:
    pip3 install requests supabase
"""

import argparse
import json
import math
import os
import re
import struct
import sys
import time
import unicodedata
from datetime import datetime
from difflib import SequenceMatcher

import requests

# ============================================================
# KONFIGURATION
# ============================================================
BASE_URL = "https://www.zuerich.com"
DATA_PATH = "/en/api/v2/data"

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

# Suchmittelpunkt fuer die POIs aus der Datenbank: Zuerich Altstadt.
# Das API von Zuerich Tourismus deckt Stadt und Region ab, entsprechend
# werden nur POIs in diesem Umkreis ueberhaupt geprueft.
ZURICH_LAT = 47.3769
ZURICH_LNG = 8.5417
DEFAULT_RADIUS_KM = 25

# Ein Treffer muss beide Kriterien erfuellen (siehe match_pois).
DEFAULT_MAX_DISTANCE_M = 150
NAME_RATIO_STRICT = 0.86   # bis DEFAULT_MAX_DISTANCE_M
NAME_RATIO_CLOSE = 0.70    # innerhalb von CLOSE_DISTANCE_M (gleiches Gebaeude)
CLOSE_DISTANCE_M = 40

# Mehr als das braucht das Foto-Karussell im Detail-Sheet nicht.
DEFAULT_MAX_IMAGES = 5

# Bildnachweis: Die Daten stehen unter der Lizenz von Zuerich Tourismus zur
# Verfuegung und verlangen die Nennung der Quelle (siehe Open-Data-Seite).
# Umlaut hier bewusst: der Wert landet als Bildnachweis in der App-Oberflaeche.
IMAGE_SOURCE = "Zürich Tourismus (zuerich.com)"

# Sprachreihenfolge fuer mehrsprachige Felder.
LANGUAGES = ("de", "en", "fr", "it")

# Generische Bestandteile, die fuer den Namensvergleich nichts beitragen.
GENERIC_TOKENS = {
    "restaurant", "ristorante", "hotel", "bar", "cafe", "caffe", "coffee",
    "bistro", "brasserie", "pub", "museum", "kino", "cinema", "theater",
    "theatre", "shop", "store", "boutique", "zurich", "zuerich", "das",
    "der", "die", "the", "zum", "zur", "am", "im", "in", "of", "and", "und",
}

HEADERS = {
    "Accept": "application/json",
    "User-Agent": "AR-Mikronavigation/1.0 (Bachelorarbeit; Open-Data-Import)",
}


# ============================================================
# API-ZUGRIFF
# ============================================================
def fetch_json(url, attempts=3):
    """GET mit kleiner Wiederholung - das API antwortet gelegentlich langsam."""
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            response = requests.get(url, headers=HEADERS, timeout=60)
            response.raise_for_status()
            return response.json()
        except Exception as error:  # Netz, Timeout, ungueltiges JSON
            last_error = error
            if attempt < attempts:
                time.sleep(2 * attempt)
    raise RuntimeError("Abruf fehlgeschlagen: " + url + " (" + str(last_error) + ")")


def fetch_categories():
    """Liste aller Kategorien: [{id, name, path, parent}, ...]."""
    data = fetch_json(BASE_URL + DATA_PATH)
    if not isinstance(data, list):
        raise RuntimeError("Unerwartete Antwort auf " + DATA_PATH)
    return [c for c in data if isinstance(c, dict) and c.get("id") is not None]


def category_url(category):
    """Bevorzugt den vom API gelieferten Pfad, sonst ?id=<id>."""
    path = category.get("path")
    if isinstance(path, str) and path:
        return BASE_URL + path if path.startswith("/") else path
    return BASE_URL + DATA_PATH + "?id=" + str(category["id"])


def fetch_entries(categories, pause=0.3):
    """Alle Eintraege aller Kategorien, dedupliziert ueber identifier."""
    entries = {}
    for index, category in enumerate(categories, start=1):
        url = category_url(category)
        label = local_text(category.get("name")) or str(category.get("id"))
        try:
            data = fetch_json(url)
        except RuntimeError as error:
            print("  ! Kategorie " + label + " uebersprungen: " + str(error))
            continue

        if not isinstance(data, list):
            continue

        new = 0
        for node in data:
            if not isinstance(node, dict):
                continue
            key = entry_key(node)
            if key and key not in entries:
                entries[key] = node
                new += 1

        print("  [" + str(index) + "/" + str(len(categories)) + "] "
              + label + ": " + str(len(data)) + " Eintraege (" + str(new) + " neu)")
        time.sleep(pause)

    return list(entries.values())


def entry_key(node):
    """Stabiler Schluessel eines Eintrags fuer die Deduplizierung."""
    for field in ("identifier", "@id", "id", "url"):
        value = node.get(field)
        if isinstance(value, (str, int)) and str(value).strip():
            return str(value)
    name = local_text(node.get("name"))
    lat, lng = entry_coordinates(node)
    if name and lat is not None:
        return name + "|" + str(round(lat, 5)) + "|" + str(round(lng, 5))
    return None


# ============================================================
# FELD-EXTRAKTION (Schema.org, mehrsprachig)
# ============================================================
def local_text(value):
    """Holt aus einem (evtl. mehrsprachigen) Feld einen lesbaren Text."""
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        for item in value:
            text = local_text(item)
            if text:
                return text
        return None
    if isinstance(value, dict):
        for language in LANGUAGES:
            text = value.get(language)
            if isinstance(text, str) and text.strip():
                return text.strip()
        # Schema.org-Objekte: {"name": ...} bzw. {"@value": ...}
        for field in ("name", "@value", "value", "text", "legalName"):
            if field in value:
                text = local_text(value[field])
                if text:
                    return text
    return None


def entry_coordinates(node):
    """Breite/Laenge eines Eintrags (geoCoordinates bzw. geo)."""
    for field in ("geoCoordinates", "geo", "location"):
        geo = node.get(field)
        if isinstance(geo, list):
            geo = geo[0] if geo else None
        if not isinstance(geo, dict):
            continue
        lat = to_float(geo.get("latitude"))
        lng = to_float(geo.get("longitude"))
        if lat is not None and lng is not None:
            return lat, lng
    return None, None


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def image_objects(node):
    """`image` (Hauptbild) und `photo` (weitere Bilder) als flache Liste."""
    raw = []
    for field in ("image", "photo", "images", "photos"):
        value = node.get(field)
        if value is None:
            continue
        if isinstance(value, (list, tuple)):
            raw.extend(value)
        else:
            raw.append(value)
    return raw


def extract_images(node, limit):
    """Bild-URLs mit Bildunterschrift und Rechteinhaber, dedupliziert."""
    images = []
    seen = set()

    for item in image_objects(node):
        if isinstance(item, str):
            url, caption, credit = item.strip(), None, None
        elif isinstance(item, dict):
            url = None
            for field in ("url", "contentUrl", "@id", "src"):
                url = local_text(item.get(field))
                if url:
                    break
            caption = (local_text(item.get("caption"))
                       or local_text(item.get("description"))
                       or local_text(item.get("name")))
            credit = (local_text(item.get("copyrightHolder"))
                      or local_text(item.get("creditText"))
                      or local_text(item.get("author"))
                      or local_text(item.get("copyrightNotice")))
        else:
            continue

        if not url or not url.startswith("http"):
            continue
        if url in seen:
            continue
        seen.add(url)

        image = {"url": url}
        if caption:
            image["caption"] = caption
        image["credit"] = credit or IMAGE_SOURCE
        images.append(image)

        if len(images) >= limit:
            break

    return images


def entry_to_place(node, max_images):
    """Ein API-Eintrag, reduziert auf das, was fuer die Zuordnung noetig ist."""
    lat, lng = entry_coordinates(node)
    name = local_text(node.get("name"))
    images = extract_images(node, max_images)

    if not name or lat is None or not images:
        return None

    return {
        "identifier": entry_key(node),
        "name": name,
        "latitude": lat,
        "longitude": lng,
        "images": images,
        "url": local_text(node.get("url")),
    }


# ============================================================
# ZUORDNUNG API-EINTRAG -> POI
# ============================================================
def strip_accents(text):
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def normalize_name(name):
    """Kleinschreibung, ohne Akzente/Satzzeichen - Basis fuer den Vergleich."""
    text = strip_accents((name or "").lower())
    text = (text.replace("ae", "a").replace("oe", "o").replace("ue", "u")
                .replace("&", " und "))
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def core_name(name):
    """Normalisierter Name ohne generische Bestandteile (restaurant, hotel...)."""
    tokens = [t for t in normalize_name(name).split() if t not in GENERIC_TOKENS]
    return " ".join(tokens) if tokens else normalize_name(name)


def name_similarity(a, b):
    """0..1 - vergleicht sowohl den vollen als auch den Kern-Namen."""
    full = SequenceMatcher(None, normalize_name(a), normalize_name(b)).ratio()
    core_a, core_b = core_name(a), core_name(b)
    core = SequenceMatcher(None, core_a, core_b).ratio()
    # Enthaltensein zaehlt voll ("Cafe Henrici" vs. "Henrici").
    if core_a and core_b and (core_a in core_b or core_b in core_a):
        core = max(core, 0.95)
    return max(full, core)


def haversine_m(lat1, lng1, lat2, lng2):
    radius = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)
    a = (math.sin(d_phi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2)
    return 2 * radius * math.asin(math.sqrt(a))


def is_match(distance_m, ratio, max_distance_m):
    """Treffer nur bei raeumlicher UND namentlicher Uebereinstimmung."""
    if distance_m <= CLOSE_DISTANCE_M and ratio >= NAME_RATIO_CLOSE:
        return True
    return distance_m <= max_distance_m and ratio >= NAME_RATIO_STRICT


def match_pois(pois, places, max_distance_m):
    """Bester Treffer je POI. Ein API-Eintrag darf mehrere POIs bedienen
    (Hotel und dessen Restaurant teilen sich dieselbe Adresse)."""
    matches = []
    for poi in pois:
        best = None
        for place in places:
            distance = haversine_m(poi["latitude"], poi["longitude"],
                                   place["latitude"], place["longitude"])
            if distance > max_distance_m:
                continue
            ratio = name_similarity(poi["name"], place["name"])
            if not is_match(distance, ratio, max_distance_m):
                continue
            # Naehe leicht gewichten, damit bei gleichem Namen der naehere gewinnt.
            score = ratio - distance / (max_distance_m * 20)
            if best is None or score > best["score"]:
                best = {"place": place, "distance_m": distance,
                        "ratio": ratio, "score": score}

        if best:
            matches.append({
                "poi_id": poi.get("id"),
                "poi_source": poi.get("source"),
                "poi_source_id": poi.get("source_id"),
                "poi_name": poi["name"],
                "matched_name": best["place"]["name"],
                "distance_m": round(best["distance_m"], 1),
                "name_ratio": round(best["ratio"], 3),
                "identifier": best["place"]["identifier"],
                "images": best["place"]["images"],
                "accessibility_details": poi.get("accessibility_details") or {},
            })
    return matches


# ============================================================
# POIs LADEN
# ============================================================
def supabase_client():
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("WARNUNG: SUPABASE_URL und SUPABASE_SERVICE_KEY muessen gesetzt sein")
        print("         (oder --pois-file <backup.json> fuer eine Vorschau nutzen)")
        sys.exit(1)
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def load_pois_from_supabase(client, radius_km, page_size=1000):
    """Alle POIs der Tabelle, seitenweise, danach in Python auf den Umkreis
    gefiltert. Bewusst nicht ueber die RPC pois_within_radius: die hat ein
    LIMIT 500 und wuerde bei einem grossen Radius POIs unterschlagen."""
    pois = []
    start = 0
    while True:
        # Sortiert, damit die Seiten sich nicht ueberlappen oder Luecken lassen.
        result = client.table("poi_accessibility") \
            .select("id,name,location,source,source_id,accessibility_details") \
            .order("id") \
            .range(start, start + page_size - 1) \
            .execute()
        rows = result.data or []
        if not rows:
            break

        for row in rows:
            position = parse_location(row.get("location"))
            if not position:
                continue
            lat, lng = position
            if haversine_m(ZURICH_LAT, ZURICH_LNG, lat, lng) > float(radius_km) * 1000:
                continue
            pois.append({
                "id": row.get("id"),
                "name": row.get("name") or "",
                "latitude": lat,
                "longitude": lng,
                "source": row.get("source"),
                "source_id": row.get("source_id"),
                "accessibility_details": row.get("accessibility_details") or {},
            })

        if len(rows) < page_size:
            break
        start += page_size

    return pois


POINT_PATTERN = re.compile(r"POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)", re.IGNORECASE)


def parse_location(value):
    """(lat, lng) aus einer PostGIS-Geography. PostgREST liefert sie als
    Hex-EWKB, je nach Konfiguration auch als GeoJSON oder WKT."""
    if isinstance(value, dict):
        coordinates = value.get("coordinates")
        if isinstance(coordinates, (list, tuple)) and len(coordinates) >= 2:
            return float(coordinates[1]), float(coordinates[0])
        return None
    if not isinstance(value, str):
        return None

    match = POINT_PATTERN.search(value)
    if match:
        return float(match.group(2)), float(match.group(1))
    return parse_ewkb_point(value)


def parse_ewkb_point(text):
    """Hex-EWKB eines POINT auspacken (z. B. 0101000020E6100000...)."""
    try:
        raw = bytes.fromhex(text.strip())
    except ValueError:
        return None
    if len(raw) < 21:
        return None

    order = "<" if raw[0] == 1 else ">"
    type_code = struct.unpack(order + "I", raw[1:5])[0]
    if type_code & 0xFF != 1:  # nur POINT
        return None

    offset = 5
    if type_code & 0x20000000:  # SRID mitgeliefert (EWKB)
        offset += 4
    if len(raw) < offset + 16:
        return None

    lng, lat = struct.unpack(order + "dd", raw[offset:offset + 16])
    return lat, lng


def load_pois_from_file(path):
    """POIs aus einem Import-Backup (z. B. pois_ginto_*.json) - fuer eine
    Vorschau ohne Supabase-Zugang. Ohne id, dafuer mit source_id."""
    with open(path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)

    pois = []
    for row in raw:
        match = POINT_PATTERN.search(row.get("location") or "")
        if not match:
            continue
        pois.append({
            "id": None,
            "name": row.get("name") or "",
            "longitude": float(match.group(1)),
            "latitude": float(match.group(2)),
            "source": row.get("source"),
            "source_id": row.get("source_id"),
            "accessibility_details": row.get("accessibility_details") or {},
        })
    return pois


# ============================================================
# SCHREIBEN
# ============================================================
def merged_details(match):
    """accessibility_details des POI plus Bilder und Bildnachweis."""
    details = dict(match["accessibility_details"])
    details["images"] = match["images"]
    details["image_source"] = IMAGE_SOURCE
    return details


def images_patch(match):
    """Nur die Felder, die dieser Import setzt - fuer das SQL-Merge."""
    return {"images": match["images"], "image_source": IMAGE_SOURCE}


def write_sql(matches, path):
    """Idempotentes SQL fuer den Supabase-SQL-Editor (ohne Service-Key).
    `||` merged in das bestehende JSONB, alle anderen Felder bleiben."""
    lines = [
        "-- AR-Mikronavigation - POI-Bilder aus dem Zuerich-Tourismus-API",
        "-- Quelle: " + BASE_URL + DATA_PATH + " (Open Data 2.0, " + IMAGE_SOURCE + ")",
        "-- Erzeugt: " + datetime.now().isoformat(timespec="seconds"),
        "-- Setzt accessibility_details.images/.image_source; mehrfaches",
        "-- Ausfuehren ueberschreibt dieselben Felder und ist damit idempotent.",
        "",
        "BEGIN;",
        "",
    ]

    written = 0
    for match in matches:
        patch = json.dumps(images_patch(match), ensure_ascii=False).replace("'", "''")
        if match.get("poi_id"):
            where = "id = '" + str(match["poi_id"]) + "'"
        elif match.get("poi_source_id"):
            where = ("source = '" + str(match["poi_source"]) + "' AND source_id = '"
                     + str(match["poi_source_id"]).replace("'", "''") + "'")
        else:
            continue
        lines.append("UPDATE poi_accessibility")
        lines.append("SET accessibility_details = "
                     "COALESCE(accessibility_details, '{}'::jsonb) || '" + patch + "'::jsonb")
        lines.append("WHERE " + where + ";")
        lines.append("")
        written += 1

    lines.append("COMMIT;")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return written


def update_supabase(client, matches):
    print("\nSchreibe Bilder zu " + str(len(matches)) + " POIs in Supabase...")
    ok, failed = 0, 0
    for index, match in enumerate(matches, start=1):
        if not match.get("poi_id"):
            failed += 1
            continue
        try:
            client.table("poi_accessibility") \
                .update({"accessibility_details": merged_details(match)}) \
                .eq("id", match["poi_id"]) \
                .execute()
            ok += 1
        except Exception as error:
            failed += 1
            print("  ! " + match["poi_name"] + ": " + str(error))
        if index % 25 == 0:
            print("  " + str(index) + "/" + str(len(matches)) + " aktualisiert")

    print("OK " + str(ok) + " POIs aktualisiert, " + str(failed) + " fehlgeschlagen")


# ============================================================
# MAIN
# ============================================================
def parse_args():
    parser = argparse.ArgumentParser(
        description="Fotos aus dem Zuerich-Tourismus-API zu den POIs ergaenzen")
    parser.add_argument("--dry-run", action="store_true",
                        help="nur Zuordnung zeigen, nichts schreiben")
    parser.add_argument("--pois-file",
                        help="POIs aus einem Import-Backup statt aus Supabase lesen "
                             "(Vorschau ohne Zugangsdaten)")
    parser.add_argument("--categories",
                        help="nur diese Kategorie-IDs abfragen, kommagetrennt "
                             "(z. B. 72,101 fuer Sehenswuerdigkeiten und Gastronomie)")
    parser.add_argument("--radius-km", type=float, default=DEFAULT_RADIUS_KM,
                        help="Umkreis um Zuerich, in dem POIs geprueft werden "
                             "(Standard: " + str(DEFAULT_RADIUS_KM) + ")")
    parser.add_argument("--max-distance-m", type=float, default=DEFAULT_MAX_DISTANCE_M,
                        help="maximale Distanz fuer einen Treffer "
                             "(Standard: " + str(DEFAULT_MAX_DISTANCE_M) + ")")
    parser.add_argument("--max-images", type=int, default=DEFAULT_MAX_IMAGES,
                        help="hoechstens so viele Bilder je POI "
                             "(Standard: " + str(DEFAULT_MAX_IMAGES) + ")")
    parser.add_argument("--yes", action="store_true",
                        help="ohne Rueckfrage in Supabase schreiben")
    return parser.parse_args()


def main():
    args = parse_args()

    print("=" * 60)
    print("Zuerich-Tourismus Bilder-Import - AR-Mikronavigation")
    print("API: " + BASE_URL + DATA_PATH)
    print("=" * 60)

    # 1. Kategorien
    print("\nLade Kategorien...")
    categories = fetch_categories()
    if args.categories:
        wanted = {c.strip() for c in args.categories.split(",") if c.strip()}
        categories = [c for c in categories if str(c["id"]) in wanted]
    print("OK " + str(len(categories)) + " Kategorien")

    # 2. Eintraege
    print("\nLade Eintraege (ein Request je Kategorie)...")
    entries = fetch_entries(categories)
    print("OK " + str(len(entries)) + " Eintraege insgesamt")

    places = [p for p in (entry_to_place(e, args.max_images) for e in entries) if p]
    image_count = sum(len(p["images"]) for p in places)
    print("OK " + str(len(places)) + " Eintraege mit Koordinaten und Bild "
          + "(" + str(image_count) + " Bilder)")

    if not places:
        print("Keine Bilder gefunden - Abbruch.")
        sys.exit(1)

    # 3. POIs
    client = None
    if args.pois_file:
        print("\nLade POIs aus " + args.pois_file + "...")
        pois = load_pois_from_file(args.pois_file)
    else:
        client = supabase_client()
        print("\nLade POIs aus Supabase (Umkreis " + str(args.radius_km) + " km)...")
        pois = load_pois_from_supabase(client, args.radius_km)
    print("OK " + str(len(pois)) + " POIs")

    # 4. Zuordnung
    print("\nOrdne Bilder den POIs zu (max. " + str(args.max_distance_m) + " m)...")
    matches = match_pois(pois, places, args.max_distance_m)
    print("OK " + str(len(matches)) + " von " + str(len(pois)) + " POIs bekommen Bilder")

    for match in matches[:15]:
        print("  - " + match["poi_name"] + "  <-  " + match["matched_name"]
              + "  (" + str(match["distance_m"]) + " m, "
              + str(int(match["name_ratio"] * 100)) + "% Name, "
              + str(len(match["images"])) + " Bilder)")
    if len(matches) > 15:
        print("  ... und " + str(len(matches) - 15) + " weitere")

    if not matches:
        print("Keine Zuordnung moeglich - nichts zu schreiben.")
        return

    # 5. Backup + SQL
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = "poi_images_zuerich_" + stamp + ".json"
    with open(backup_file, "w", encoding="utf-8") as handle:
        json.dump([{k: v for k, v in m.items() if k != "accessibility_details"}
                   for m in matches], handle, indent=2, ensure_ascii=False)
    print("\nOK Backup gespeichert: " + backup_file)

    sql_file = "poi_images_zuerich_" + stamp + ".sql"
    print("OK SQL geschrieben: " + sql_file + " ("
          + str(write_sql(matches, sql_file)) + " UPDATEs)")

    # 6. Schreiben
    if args.dry_run:
        print("\n--dry-run: nichts in Supabase geschrieben.")
        return
    if args.pois_file:
        print("\nOhne POI-IDs (--pois-file) wird nicht direkt geschrieben - "
              "das erzeugte SQL im Supabase-SQL-Editor ausfuehren.")
        return

    if not args.yes:
        confirm = input("\nIn Supabase schreiben? (y/n): ")
        if confirm.lower() != "y":
            print("Import abgebrochen.")
            return

    update_supabase(client, matches)
    print("\nOK Import abgeschlossen!")


if __name__ == "__main__":
    main()