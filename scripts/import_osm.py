#!/usr/bin/env python3
"""
OSM Import Script - Omina
Laedt Barrieren-Daten aus OpenStreetMap (Overpass API) fuer das Testgebiet
Altstadt Zuerich und schreibt sie in die Supabase barriers Tabelle.

Ausgewertet werden die Tags, die das OSM-Wiki im Projekt Rollstuhl-Routing
auffuehrt (https://wiki.openstreetmap.org/wiki/Wheelchair_routing):

    Wegeigenschaften   surface, smoothness, tracktype, width, incline
    Kanten             kerb, kerb:height, sloped_curb (auch :start/:end)
    Gehwege            sidewalk:left|right|both:<eigenschaft>
    Hindernisse        highway=steps (+step_count), barrier=*, wheelchair=no
    Uebergaenge        highway=crossing mit kerb/sloped_curb/wheelchair

Die Schaetzwerte bei fehlender Messung folgen DIN 18024-1, wie sie das Wiki
zusammenfasst (Bordstein max. 3 cm, Nebenweg min. 90 cm, Laengsneigung 3 %
bzw. 6 % mit Verweilplaetzen). Dieselben Werte stehen in der App unter
Services/AccessibilityStandard.swift.

Verwendung:
    python3 import_osm.py

Voraussetzungen:
    pip3 install requests supabase
"""

import os
import sys
import json
import time
import math
import requests
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict
from supabase import create_client, Client


# Alle erzeugten Backups und SQL-Dateien landen an einer festen Stelle im Repo
# (data/exports/) statt im jeweiligen Arbeitsverzeichnis – so liegen sie immer
# beieinander, egal von wo das Script gestartet wurde.
EXPORT_DIR = Path(__file__).resolve().parent.parent / "data" / "exports"


def export_path(filename: str) -> str:
    """Pfad einer erzeugten Datei unter data/exports/ (Ordner wird angelegt)."""
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    return str(EXPORT_DIR / filename)


# ============================================================
# KONFIGURATION
# ============================================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

# Anzeigegebiet Kreis 1 Stadt Zuerich (Bounding Box: Altstadt mit den
# Quartieren Rathaus, Hochschulen, Lindenhof, City)
BBOX = "47.363,8.529,47.379,8.551"

# Overpass API Endpoints (Haupt-Instanz + Mirror als Fallback).
# Wichtig: overpass-api.de blockiert den Default-User-Agent von
# python-requests mit "406 Not Acceptable" – darum unten der eigene
# User-Agent-Header.
OVERPASS_URLS = [
    os.getenv("OVERPASS_URL", "https://overpass-api.de/api/interpreter"),
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.openstreetmap.fr/api/interpreter",
]

REQUEST_HEADERS = {
    "User-Agent": "omina-osm-import/1.0 (Bachelor-Projekt Omina)"
}

# Overpass antwortet unter Last oft mit 504 Gateway Timeout – dann hilft
# meist einfach erneut versuchen.
MAX_ATTEMPTS_PER_URL = 3
RETRY_WAIT_SECONDS = 20


# ============================================================
# NORMWERTE (DIN 18024-1, siehe OSM-Wiki "Wheelchair routing")
# Spiegelbild von Services/AccessibilityStandard.swift in der App.
# ============================================================
NORM_MAX_KERB_CM = 3.0            # Schwellen/Bordsteine
NORM_MIN_SIDE_WAY_WIDTH_CM = 90.0 # Nebenweg
NORM_MIN_MAIN_WAY_WIDTH_CM = 150.0
NORM_MAX_INCLINE_PERCENT = 3.0
NORM_MAX_INCLINE_WITH_REST_PERCENT = 6.0


# ============================================================
# DEFAULT-MAPPING (NFA-15: bei Unsicherheit eher warnen)
# ============================================================
# kerb=* ohne kerb:height: lowered entspricht dem Normwert, raised liegt
# klar darueber (typischer Zuercher Trottoirrand).
KERB_HEIGHT_DEFAULTS = {
    "flush": 0,
    "lowered": NORM_MAX_KERB_CM,
    "raised": 8,
    "yes": 8,
    "no": 0,
}

# sloped_curb=yes/no (Wiki-Tag): yes = abgesenkt, no = nicht abgesenkt.
SLOPED_CURB_DEFAULTS = {
    "yes": NORM_MAX_KERB_CM,
    "no": 8,
    "both": NORM_MAX_KERB_CM,
    "at_grade": 0,
    "flush": 0,
}

INCLINE_DEFAULT_PERCENT = 8.0

# Nur oberhalb der Breite eines Hauptwegs gilt eine Stelle nicht mehr als eng.
NARROW_MAX_WIDTH_CM = 200.0

# Seitlicher Versatz, mit dem Gehweg-Eigenschaften (sidewalk:left/right:*)
# neben die Strassenachse gelegt werden, damit sie dort erscheinen, wo man
# tatsaechlich faehrt.
SIDEWALK_OFFSET_M = 4.0

# Oberflaechen, die fuer Rollstuhlnutzende relevant sind (Wiki-Tabelle
# "Path properties"). Die Bewertung gegen das persoenliche Profil macht die
# App (OSMSurfaceRating), hier wird nur eingesammelt.
RELEVANT_SURFACES = [
    "cobblestone", "unhewn_cobblestone", "cobblestone_coarse", "cobblestone_fine",
    "sett", "grass_paver", "gravel", "fine_gravel", "pebblestone", "sand",
    "ground", "dirt", "earth", "mud", "grass", "woodchips", "unpaved",
]

# smoothness-Stufen ab "intermediate" (Wiki: Rollstuhl faehrt bis
# intermediate) und Wegequalitaet ab grade2.
RELEVANT_SMOOTHNESS = [
    "intermediate", "bad", "very_bad", "horrible", "very_horrible", "impassable",
]
RELEVANT_TRACKTYPES = ["grade2", "grade3", "grade4", "grade5"]

# Gehweg-Eigenschaften nach dem Wiki-Schema sidewalk:<seite>:<eigenschaft>.
SIDEWALK_SIDES = ["left", "right", "both"]
SIDEWALK_PROPERTIES = [
    "surface", "smoothness", "width", "incline", "sloped_curb", "kerb:height",
]

# barrier=* (Wiki-Abschnitt "Obstacles/Accessibility"): Sperren, die ohne
# Weiteres nicht passierbar sind, und solche, die nur ueber ihre Durchlass-
# breite zaehlen.
BLOCKING_BARRIERS = [
    "stile", "turnstile", "kissing_gate", "full-height_turnstile", "hampshire_gate",
]
WIDTH_BARRIERS = [
    "bollard", "gate", "cycle_barrier", "block", "lift_gate", "swing_gate",
    "chain", "planter", "barrier_board",
]


# ============================================================
# OVERPASS QUERY
# ============================================================
def build_overpass_query(bbox):
    """Alle im Wiki gelisteten rollstuhlrelevanten Tags im Testgebiet."""
    surfaces = "|".join(RELEVANT_SURFACES)
    smoothness = "|".join(RELEVANT_SMOOTHNESS)
    tracktypes = "|".join(RELEVANT_TRACKTYPES)
    # Schluessel-Regex: sidewalk:<seite>:<eigenschaft> (Overpass erlaubt
    # regulaere Ausdruecke auf Schluesseln in der Form [~"key"~"value"]).
    sidewalk_keys = ("^sidewalk:(" + "|".join(SIDEWALK_SIDES) + "):("
                     + "|".join(SIDEWALK_PROPERTIES) + ")$")
    sidewalk_filter = 'way[~"' + sidewalk_keys + '"~"."]'
    b = "(" + bbox + ")"
    return """
    [out:json][timeout:300];
    (
      // Stufen und Hindernisse
      way["highway"="steps"]""" + b + """;
      node["barrier"]""" + b + """;
      way["barrier"]""" + b + """;

      // Bordsteine und Uebergaenge
      node["kerb"]""" + b + """;
      way["kerb"]""" + b + """;
      node["kerb:height"]""" + b + """;
      way["kerb:height"]""" + b + """;
      node["sloped_curb"]""" + b + """;
      way["sloped_curb"]""" + b + """;
      way["sloped_curb:start"]""" + b + """;
      way["sloped_curb:end"]""" + b + """;
      node["highway"="crossing"]""" + b + """;

      // Wegeigenschaften
      way["incline"]""" + b + """;
      way["surface"~"^(""" + surfaces + """)$"]""" + b + """;
      way["smoothness"~"^(""" + smoothness + """)$"]""" + b + """;
      way["tracktype"~"^(""" + tracktypes + """)$"]""" + b + """;
      way["width"]""" + b + """;

      // Gehweg-Eigenschaften laengs der Strasse
      """ + sidewalk_filter + b + """;

      // Ausdruecklich als nicht rollstuhlgerecht getaggte Punkte
      node["wheelchair"="no"]""" + b + """;
    );
    out body geom;
    """


def fetch_osm_data(query):
    last_error = None
    for url in OVERPASS_URLS:
        for attempt in range(1, MAX_ATTEMPTS_PER_URL + 1):
            print("Lade Daten aus Overpass API (" + url + ", Versuch "
                  + str(attempt) + "/" + str(MAX_ATTEMPTS_PER_URL) + ")...")
            try:
                response = requests.post(
                    url,
                    data={"data": query},
                    headers=REQUEST_HEADERS,
                    timeout=300,
                )
                response.raise_for_status()
                data = response.json()
                print("OK " + str(len(data.get('elements', []))) + " Elemente geladen")
                return data
            except requests.RequestException as e:
                last_error = e
                print("WARNUNG: fehlgeschlagen (" + str(e) + ")")
                if attempt < MAX_ATTEMPTS_PER_URL:
                    print("Warte " + str(RETRY_WAIT_SECONDS) + " s vor erneutem Versuch...")
                    time.sleep(RETRY_WAIT_SECONDS)
        print("Wechsle auf naechsten Mirror...")
    print("FEHLER: Keine Overpass-Instanz erreichbar. Spaeter erneut versuchen.")
    raise last_error


# ============================================================
# HILFSFUNKTIONEN: Geometrie und Werte
# ============================================================
def element_point(element, where="mid"):
    """(lat, lng) eines Elements. Nodes direkt, Ways am Anfang, in der Mitte
    oder am Ende - die Wiki-Tags sloped_curb:start/:end beziehen sich auf die
    Digitalisierrichtung des Wegs."""
    if element.get("type") == "node" or element.get("lat") is not None:
        return element.get("lat"), element.get("lon")

    geom = element.get("geometry", [])
    if not geom:
        return None, None
    if where == "start":
        point = geom[0]
    elif where == "end":
        point = geom[-1]
    else:
        point = geom[len(geom) // 2]
    return point["lat"], point["lon"]


def way_bearing(element, where="mid"):
    """Kompasskurs (Grad, 0 = Nord) des Wegs an der betrachteten Stelle.
    Grundlage fuer den seitlichen Versatz der Gehweg-Eigenschaften."""
    geom = element.get("geometry", [])
    if len(geom) < 2:
        return None
    if where == "start":
        a, b = geom[0], geom[1]
    elif where == "end":
        a, b = geom[-2], geom[-1]
    else:
        mid = len(geom) // 2
        a, b = geom[max(mid - 1, 0)], geom[min(mid, len(geom) - 1)]
        if a is b:
            a, b = geom[0], geom[-1]

    d_lat = b["lat"] - a["lat"]
    d_lng = (b["lon"] - a["lon"]) * math.cos(math.radians(a["lat"]))
    if d_lat == 0 and d_lng == 0:
        return None
    return (math.degrees(math.atan2(d_lng, d_lat)) + 360) % 360


def offset_coordinate(lat, lng, bearing_deg, distance_m):
    """Koordinate, die distance_m in Richtung bearing_deg entfernt liegt
    (Flach-Erde-Naeherung, fuer wenige Meter mehr als genau)."""
    d_lat = distance_m * math.cos(math.radians(bearing_deg)) / 111320.0
    d_lng = distance_m * math.sin(math.radians(bearing_deg)) / (
        111320.0 * math.cos(math.radians(lat))
    )
    return lat + d_lat, lng + d_lng


def parse_length_cm(raw):
    """OSM-Laengenangabe in Zentimetern. Ohne Einheit sind es laut
    OSM-Konvention Meter (das Wiki notiert 15 cm als 0.15); "3 cm", "0.03 m"
    und "30 mm" werden ebenfalls verstanden.
    Rueckgabe: (wert_cm, "measured") oder (None, None)."""
    if raw is None:
        return None, None
    text = str(raw).strip().lower().replace(",", ".")
    try:
        if text.endswith("cm"):
            return float(text[:-2].strip()), "measured"
        if text.endswith("mm"):
            return float(text[:-2].strip()) / 10.0, "measured"
        if text.endswith("m"):
            return float(text[:-1].strip()) * 100.0, "measured"
        return float(text) * 100.0, "measured"
    except ValueError:
        return None, None


def parse_curb_height_cm(raw, defaults):
    """Bordsteinhoehe aus einem Mass ODER aus einem Schluesselwort
    (kerb=lowered, sloped_curb=yes ...). Rueckgabe wie parse_length_cm."""
    height_cm, source = parse_length_cm(raw)
    if height_cm is not None:
        return height_cm, source
    key = str(raw).strip().lower()
    if key in defaults:
        return float(defaults[key]), "estimated"
    return None, None


def parse_percent(raw):
    """Neigungsangabe in Prozent (Wiki: incline=xy%). Grad-Angaben werden
    umgerechnet, Schluesselwoerter (up/down/steep) auf den Schaetzwert."""
    if raw is None:
        return None, None
    text = str(raw).strip().lower().replace(",", ".")
    try:
        if text.endswith("%"):
            return abs(float(text[:-1].strip())), "measured"
        if text.endswith("°") or text.endswith("deg"):
            degrees = float(text.rstrip("deg°").strip())
            return abs(math.tan(math.radians(degrees)) * 100.0), "measured"
        return abs(float(text)), "measured"
    except ValueError:
        return INCLINE_DEFAULT_PERCENT, "estimated"


def barrier_at(btype, subtype, value, unit, value_source, lat, lng):
    """Einheitlicher Rueckgabewert der Parser."""
    if lat is None or lng is None:
        return None
    return {
        "type": btype,
        "subtype": subtype,
        # Auf eine Nachkommastelle runden: Aus 1.1 m werden sonst
        # 110.00000000000001 cm.
        "value": round(value, 1) if value is not None else None,
        "unit": unit,
        "value_source": value_source,
        "lat": lat,
        "lng": lng,
    }


# ============================================================
# DATEN-MAPPING: OSM -> barriers
# ============================================================
def parse_kerb(element):
    """kerb=* (+ kerb:height) an Knoten und Wegen."""
    tags = element.get("tags", {})
    kerb_type = tags.get("kerb")
    if not kerb_type:
        return None

    height_cm, value_source = parse_length_cm(tags.get("kerb:height"))
    if height_cm is None:
        height_cm = float(KERB_HEIGHT_DEFAULTS.get(kerb_type, 0))
        value_source = "estimated"

    lat, lng = element_point(element)
    return barrier_at(
        "curb", "kerb_" + kerb_type, height_cm, "cm", value_source, lat, lng
    )


def parse_sloped_curb(element):
    """sloped_curb=* aus dem Wiki, inklusive der Varianten :start und :end,
    mit denen abgesenkte Bordsteine an den Enden eines Wegs getaggt werden.
    Ergaenzend kerb:height ohne begleitendes kerb=* (das deckt parse_kerb ab).
    Rueckgabe: Liste, ein Weg kann Anfang UND Ende tragen."""
    tags = element.get("tags", {})
    results = []

    candidates = [
        ("sloped_curb", "mid"),
        ("sloped_curb:start", "start"),
        ("sloped_curb:end", "end"),
    ]
    if "kerb" not in tags:
        candidates += [
            ("kerb:height", "mid"),
            ("kerb:height:start", "start"),
            ("kerb:height:end", "end"),
        ]

    for key, where in candidates:
        if key not in tags:
            continue
        height_cm, value_source = parse_curb_height_cm(tags[key], SLOPED_CURB_DEFAULTS)
        if height_cm is None:
            continue
        lat, lng = element_point(element, where)
        entry = barrier_at(
            "curb", key.replace(":", "_"), height_cm, "cm", value_source, lat, lng
        )
        if entry:
            results.append(entry)
    return results


def parse_steps(element):
    tags = element.get("tags", {})
    if tags.get("highway") != "steps":
        return None
    
    step_count = tags.get("step_count")
    try:
        count = int(step_count) if step_count else None
    except ValueError:
        count = None
    
    geom = element.get("geometry", [])
    if not geom:
        return None
    
    return {
        "type": "steps",
        "subtype": None,
        "value": float(count) if count else None,
        "unit": "count",
        "value_source": "measured" if count else "estimated",
        "lat": geom[0]["lat"],
        "lng": geom[0]["lon"],
    }


def parse_incline(element):
    """incline=* (Laengsneigung). Norm: 3 %, mit Verweilplaetzen bis 6 %."""
    tags = element.get("tags", {})
    if "incline" not in tags:
        return None

    value, value_source = parse_percent(tags["incline"])
    if value is None:
        return None

    lat, lng = element_point(element)
    return barrier_at("incline", None, value, "percent", value_source, lat, lng)


def parse_surface(element):
    """surface=* - das Material des Belags (Wiki-Tabelle "Path properties").
    Bewertet wird es in der App gegen die persoenliche Toleranz."""
    tags = element.get("tags", {})
    surface = tags.get("surface")
    if not surface or surface not in RELEVANT_SURFACES:
        return None

    lat, lng = element_point(element)
    return barrier_at("surface", surface, None, None, "measured", lat, lng)


def parse_smoothness(element):
    """smoothness=* - die Ebenheit. Laut Wiki faehrt ein Rollstuhl bis
    "intermediate"; schlechtere Stufen sind je nach Profil ein Hindernis."""
    tags = element.get("tags", {})
    smoothness = tags.get("smoothness")
    if not smoothness or smoothness not in RELEVANT_SMOOTHNESS:
        return None

    lat, lng = element_point(element)
    return barrier_at(
        "surface", "smoothness_" + smoothness, None, None, "measured", lat, lng
    )


def parse_tracktype(element):
    """tracktype=* - grade1 ist befestigt/stark verdichtet, ab grade2 wird es
    fuer Rollstuehle je nach Profil schwierig."""
    tags = element.get("tags", {})
    tracktype = tags.get("tracktype")
    if not tracktype or tracktype not in RELEVANT_TRACKTYPES:
        return None

    lat, lng = element_point(element)
    return barrier_at(
        "surface", "tracktype_" + tracktype, None, None, "measured", lat, lng
    )


def parse_narrow(element):
    """width=* - Engstellen. Norm: Nebenweg min. 90 cm, Hauptweg min. 150 cm;
    erfasst wird alles unterhalb der Hauptweg-Empfehlung."""
    tags = element.get("tags", {})
    width_cm, value_source = parse_length_cm(tags.get("width"))
    if width_cm is None or width_cm > NARROW_MAX_WIDTH_CM:
        return None

    lat, lng = element_point(element)
    return barrier_at("narrow", None, width_cm, "cm", value_source, lat, lng)


def parse_sidewalk(element):
    """sidewalk:<seite>:<eigenschaft> - die Gehweg-Tags aus dem Wiki.

    Sie haengen an der Strassenachse, gefahren wird aber auf dem Trottoir
    daneben. Die Barrieren werden deshalb quer zur Digitalisierrichtung
    versetzt: "left"/"right" beziehen sich laut Wiki genau darauf.
    Rueckgabe: Liste (eine Strasse kann links und rechts Eigenschaften haben).
    """
    tags = element.get("tags", {})
    results = []

    for side in SIDEWALK_SIDES:
        prefix = "sidewalk:" + side + ":"
        side_tags = {
            key[len(prefix):]: value
            for key, value in tags.items()
            if key.startswith(prefix)
        }
        if not side_tags:
            continue

        for where in ("mid", "start", "end"):
            # Bordstein-Absenkungen sitzen an den Wegenden, alles andere
            # gilt fuer den ganzen Abschnitt.
            if where == "mid":
                keys = ["surface", "smoothness", "width", "incline", "sloped_curb", "kerb:height"]
            else:
                keys = ["sloped_curb:" + where, "kerb:height:" + where]

            lat, lng = element_point(element, where)
            if lat is None:
                continue
            bearing = way_bearing(element, where)
            if bearing is not None and side != "both":
                offset_bearing = bearing - 90 if side == "left" else bearing + 90
                lat, lng = offset_coordinate(lat, lng, offset_bearing, SIDEWALK_OFFSET_M)

            for key in keys:
                if key not in side_tags:
                    continue
                entry = sidewalk_barrier(key, side_tags[key], side, lat, lng)
                if entry:
                    results.append(entry)

    return results


def sidewalk_barrier(key, raw_value, side, lat, lng):
    """Eine einzelne Gehweg-Eigenschaft in eine Barriere uebersetzen."""
    suffix = "_sidewalk_" + side

    if key == "surface":
        if raw_value not in RELEVANT_SURFACES:
            return None
        return barrier_at("surface", raw_value + suffix, None, None, "measured", lat, lng)

    if key == "smoothness":
        if raw_value not in RELEVANT_SMOOTHNESS:
            return None
        return barrier_at(
            "surface", "smoothness_" + raw_value, None, None, "measured", lat, lng
        )

    if key == "width":
        width_cm, value_source = parse_length_cm(raw_value)
        if width_cm is None or width_cm > NARROW_MAX_WIDTH_CM:
            return None
        return barrier_at("narrow", None, width_cm, "cm", value_source, lat, lng)

    if key == "incline":
        value, value_source = parse_percent(raw_value)
        if value is None:
            return None
        return barrier_at("incline", None, value, "percent", value_source, lat, lng)

    if key.startswith("sloped_curb") or key.startswith("kerb:height"):
        height_cm, value_source = parse_curb_height_cm(raw_value, SLOPED_CURB_DEFAULTS)
        if height_cm is None:
            return None
        return barrier_at(
            "curb", key.replace(":", "_") + suffix, height_cm, "cm", value_source, lat, lng
        )

    return None


def parse_crossing(element):
    """highway=crossing, das ausdruecklich als nicht rollstuhlgerecht getaggt
    ist (wheelchair=no) oder dessen Bordstein nicht abgesenkt ist. Kanten mit
    kerb=*/sloped_curb=* deckt parse_kerb bzw. parse_sloped_curb ab."""
    tags = element.get("tags", {})
    if tags.get("highway") != "crossing":
        return None
    if tags.get("wheelchair") != "no":
        return None

    lat, lng = element_point(element)
    return barrier_at("curb_missing", "crossing", None, None, "estimated", lat, lng)


def parse_barrier(element):
    """barrier=* aus dem Wiki-Abschnitt "Obstacles/Accessibility".

    Poller, Tore und Umlaufsperren zaehlen nur mit erfasster Durchlassbreite
    (sonst waere in der Altstadt jeder Poller eine Warnung); Drehkreuze und
    Umlaufgitter sind grundsaetzlich nicht passierbar."""
    tags = element.get("tags", {})
    barrier = tags.get("barrier")
    if not barrier:
        return None

    lat, lng = element_point(element)

    if barrier == "kerb":
        height_cm, value_source = parse_curb_height_cm(
            tags.get("kerb:height", tags.get("kerb", "raised")), KERB_HEIGHT_DEFAULTS
        )
        if height_cm is None:
            height_cm, value_source = float(KERB_HEIGHT_DEFAULTS["raised"]), "estimated"
        return barrier_at("curb", "barrier_kerb", height_cm, "cm", value_source, lat, lng)

    if barrier in BLOCKING_BARRIERS:
        return barrier_at("narrow", "barrier_" + barrier, None, None, "estimated", lat, lng)

    if barrier in WIDTH_BARRIERS:
        width_cm, value_source = parse_length_cm(
            tags.get("maxwidth", tags.get("width"))
        )
        if width_cm is None or width_cm > NARROW_MAX_WIDTH_CM:
            return None
        return barrier_at(
            "narrow", "barrier_" + barrier, width_cm, "cm", value_source, lat, lng
        )

    return None


PARSERS = [
    parse_kerb,
    parse_sloped_curb,
    parse_steps,
    parse_incline,
    parse_surface,
    parse_smoothness,
    parse_tracktype,
    parse_narrow,
    parse_sidewalk,
    parse_crossing,
    parse_barrier,
]


def osm_to_barriers(osm_data):
    barriers = []

    for element in osm_data.get("elements", []):
        for parser in PARSERS:
            result = parser(element)
            if result is None:
                continue
            # Manche Parser liefern mehrere Barrieren pro Element
            # (Weganfang/-ende, linker und rechter Gehweg).
            entries = result if isinstance(result, list) else [result]

            for entry in entries:
                if entry.get("lat") is None or entry.get("lng") is None:
                    continue
                barriers.append({
                    "type": entry["type"],
                    "subtype": entry["subtype"],
                    "value": entry["value"],
                    "unit": entry["unit"],
                    "location": "POINT(" + str(entry["lng"]) + " " + str(entry["lat"]) + ")",
                    "value_source": entry["value_source"],
                    "source": "osm",
                    "source_id": str(element.get("id", "")),
                    "source_tags": element.get("tags", {}),
                    "is_active": True,
                })

    return barriers


# ============================================================
# SUPABASE IMPORT
# ============================================================
def import_to_supabase(barriers):
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("WARNUNG: SUPABASE_URL und SUPABASE_SERVICE_KEY muessen als Env-Variablen gesetzt sein")
        sys.exit(1)
    
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    print("\nSchreibe " + str(len(barriers)) + " Barrieren in Supabase...")
    
    batch_size = 100
    for i in range(0, len(barriers), batch_size):
        batch = barriers[i:i + batch_size]
        try:
            result = supabase.table("barriers").insert(batch).execute()
            print("OK Batch " + str(i // batch_size + 1) + ": " + str(len(batch)) + " Eintraege")
        except Exception as e:
            print("FEHLER in Batch " + str(i // batch_size + 1) + ": " + str(e))
    
    print("\nOK Import abgeschlossen!")


# ============================================================
# MAIN
# ============================================================
def main():
    print("=" * 60)
    print("OSM Import - Omina")
    print("Gebiet: Kreis 1 Stadt Zuerich (" + BBOX + ")")
    print("=" * 60)
    
    query = build_overpass_query(BBOX)
    osm_data = fetch_osm_data(query)
    
    print("\nParse OSM-Daten...")
    barriers = osm_to_barriers(osm_data)
    
    type_counts = {}
    source_counts = {"measured": 0, "estimated": 0}
    for b in barriers:
        type_counts[b["type"]] = type_counts.get(b["type"], 0) + 1
        source_counts[b["value_source"]] = source_counts.get(b["value_source"], 0) + 1
    
    print("\nOK " + str(len(barriers)) + " Barrieren extrahiert:")
    for btype, count in type_counts.items():
        print("  - " + btype + ": " + str(count))
    print("\nDatenqualitaet:")
    print("  - measured: " + str(source_counts['measured']))
    print("  - estimated: " + str(source_counts['estimated']))
    
    backup_file = export_path("barriers_osm_" + datetime.now().strftime('%Y%m%d_%H%M%S') + ".json")
    with open(backup_file, "w", encoding="utf-8") as f:
        json.dump(barriers, f, indent=2, ensure_ascii=False)
    print("\nOK Backup gespeichert: " + backup_file)
    
    confirm = input("\nIn Supabase importieren? (y/n): ")
    if confirm.lower() == "y":
        import_to_supabase(barriers)
    else:
        print("Import abgebrochen.")


if __name__ == "__main__":
    main()