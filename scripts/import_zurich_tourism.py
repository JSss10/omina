#!/usr/bin/env python3
"""
Zuerich-Tourismus Import - Omina

Prueft fuer jeden bestehenden POI (ginto/OSM), ob es ihn im Open-Data-API
von Zuerich Tourismus gibt (Version 2.0,
https://www.zuerich.com/en/open-data-version-20), und uebernimmt bei einem
Treffer Fotos, Oeffnungszeiten, Telefon, Webseite und Kurzbeschreibung in
die Supabase-Tabelle poi_accessibility. POIs ohne Treffer bleiben
unveraendert - die App zeigt dort Platzhalter.

API-Aufbau (Version 2.0, nur unter /en/ verfuegbar, kein API-Key noetig):

    GET /en/api/v2/data              Liste aller Kategorien
                                     [{id, name, path, parent}, ...]
    GET /en/api/v2/data?id=<id>      Alle Eintraege einer Kategorie

Die Eintraege sind nach Schema.org aufgebaut; mehrsprachige Felder kommen
als Objekt {"de": ..., "en": ...}. Bilder stecken in `image` (Hauptbild)
und `photo`, die Position in `geoCoordinates`, die Zeiten in
`openingHours` bzw. `openingHoursSpecification`.

Zuordnung API-Eintrag -> POI: ueber die Distanz (Standard 150 m) UND die
Namensaehnlichkeit. Beides zusammen, weil in der Altstadt viele Lokale
dicht beieinanderliegen und Namen wie "Hotel Storchen" mehrfach vorkommen.

Geschrieben wird ausschliesslich in accessibility_details - genau die
Schluessel, die POI.swift liest:

    images              Liste {url, caption, credit}
    image_source        Bildnachweis
    opening_hours       Anzeigezeilen, z. B. ["Mo-Fr 09:00-18:00"]
    opening_hours_spec  strukturiert [{days: [1..7], opens, closes}]
    phone, email        Kontakt (auch aus dem Adressblock)
    website             Webseite des Ortes
    description         Beschreibungstext, von HTML befreit
    summary             Einzeiler (disambiguatingDescription)
    teaser              Kurzfassung fuer Listen (textTeaser)
    highlights          Stichpunkte (detailedInformation)
    street_address, postal_code, locality, address_line   Adresse
    price_range         Preisniveau
    updated_at          Stand der Angaben (dateModified)
    zuerich_name        gefundener Name im API (Nachvollziehbarkeit)
    zuerich_url         Detailseite auf zuerich.com
    info_source         Quellenangabe fuer die Textangaben

Verwendung:
    python3 import_zurich_tourism.py                  # Supabase lesen + schreiben
    python3 import_zurich_tourism.py --dry-run        # nur Vorschau
    python3 import_zurich_tourism.py --pois-file ../data/exports/pois_ginto_20260407_142744.json
                                               # Vorschau ohne Supabase
    python3 import_zurich_tourism.py --seed-file ../Omina/Omina/Seed/seed_pois.json
                                               # Offline-Seed der App mitpflegen

Voraussetzungen:
    pip3 install requests supabase
"""

import argparse
import html
import json
import math
import os
import re
import struct
import sys
import time
import unicodedata
from datetime import datetime
from pathlib import Path
from difflib import SequenceMatcher

import requests


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

# Quellenangabe: Die Daten stehen unter der Lizenz von Zuerich Tourismus zur
# Verfuegung und verlangen die Nennung der Quelle (siehe Open-Data-Seite).
# Umlaut hier bewusst: der Wert landet als Nachweis in der App-Oberflaeche.
IMAGE_SOURCE = "Zürich Tourismus (zuerich.com)"
INFO_SOURCE = IMAGE_SOURCE

# Kurzbeschreibung im Detail-Sheet: laenger als das liest im Sheet niemand.
MAX_DESCRIPTION_CHARS = 1200

# Hoechstzahl der Stichpunkte aus `detailedInformation`.
MAX_HIGHLIGHTS = 6

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
    "User-Agent": "Omina/1.0 (Bachelorarbeit; Open-Data-Import)",
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


# ------------------------------------------------------------
# Oeffnungszeiten
# ------------------------------------------------------------
# Schema.org nennt die Wochentage englisch (auch als URL
# https://schema.org/Monday); zuerich.com liefert je nach Feld deutsch.
DAY_NUMBERS = {
    "monday": 1, "mon": 1, "mo": 1, "montag": 1,
    "tuesday": 2, "tue": 2, "tu": 2, "di": 2, "dienstag": 2,
    "wednesday": 3, "wed": 3, "we": 3, "mi": 3, "mittwoch": 3,
    "thursday": 4, "thu": 4, "th": 4, "do": 4, "donnerstag": 4,
    "friday": 5, "fri": 5, "fr": 5, "freitag": 5,
    "saturday": 6, "sat": 6, "sa": 6, "samstag": 6,
    "sunday": 7, "sun": 7, "su": 7, "so": 7, "sonntag": 7,
    "publicholidays": 0, "feiertage": 0,
}

DAY_LABELS = {1: "Mo", 2: "Di", 3: "Mi", 4: "Do", 5: "Fr", 6: "Sa", 7: "So"}


def day_number(value):
    """Wochentag -> 1 (Montag) .. 7 (Sonntag), sonst None."""
    text = local_text(value)
    if not text:
        return None
    key = text.rsplit("/", 1)[-1].strip().lower().replace(".", "").replace(" ", "")
    number = DAY_NUMBERS.get(key)
    return number if number else None


def clock_time(value):
    """"09:00:00" / "9:00" -> "09:00"; alles andere unveraendert."""
    text = local_text(value)
    if not text:
        return None
    match = re.match(r"^(\d{1,2}):(\d{2})", text.strip())
    if not match:
        return text.strip()
    return "{:02d}:{}".format(int(match.group(1)), match.group(2))


def day_range_label(days):
    """[1,2,3,4,5] -> "Mo-Fr", [1,3] -> "Mo, Mi"."""
    ordered = sorted(set(d for d in days if d in DAY_LABELS))
    if not ordered:
        return None

    groups = []
    run = [ordered[0]]
    for day in ordered[1:]:
        if day == run[-1] + 1:
            run.append(day)
        else:
            groups.append(run)
            run = [day]
    groups.append(run)

    parts = []
    for group in groups:
        if len(group) >= 3:
            parts.append(DAY_LABELS[group[0]] + "-" + DAY_LABELS[group[-1]])
        else:
            parts.extend(DAY_LABELS[d] for d in group)
    return ", ".join(parts)


def extract_opening_hours(node):
    """(Anzeigezeilen, strukturierte Eintraege) aus openingHours bzw.
    openingHoursSpecification. Die Struktur erlaubt der App, die Zeiten des
    heutigen Wochentags hervorzuheben."""
    spec = []
    raw_spec = node.get("openingHoursSpecification")
    if isinstance(raw_spec, dict):
        raw_spec = [raw_spec]
    for item in raw_spec or []:
        if not isinstance(item, dict):
            continue
        raw_days = item.get("dayOfWeek")
        if not isinstance(raw_days, (list, tuple)):
            raw_days = [raw_days]
        days = sorted({d for d in (day_number(x) for x in raw_days) if d})
        opens, closes = clock_time(item.get("opens")), clock_time(item.get("closes"))
        if days and opens and closes:
            spec.append({"days": days, "opens": opens, "closes": closes})

    # `openingHours` kommt als kompakte Zeile ("Mo,Tu,We,Th,Fr 13:00:00-22:00:00").
    # Daraus entsteht beides: die Struktur (fuer "heute geoeffnet") und die
    # lesbare deutsche Zeile.
    raw_hours = node.get("openingHours")
    if isinstance(raw_hours, (list, tuple)):
        candidates = [local_text(h) for h in raw_hours]
    else:
        candidates = [local_text(raw_hours)]

    parsed = []
    leftovers = []
    for line in candidates:
        if not line:
            continue
        entry = parse_opening_hours_line(line)
        if entry:
            if entry not in spec:
                spec.append(entry)
            if entry not in parsed:
                parsed.append(entry)
        elif line not in leftovers:
            leftovers.append(line)

    # Anzeigezeilen aus der Struktur, sonst der unveraenderte Freitext.
    lines = []
    for item in parsed or spec:
        line = opening_hours_line(item)
        if line and line not in lines:
            lines.append(line)
    for line in leftovers:
        if line not in lines:
            lines.append(line)

    return lines, spec


def parse_opening_hours_line(line):
    """"Mo,Tu,We,Th,Fr 13:00:00-22:00:00" -> {days, opens, closes}, sonst None.
    Akzeptiert Aufzaehlungen (Mo,Tu) ebenso wie Spannen (Mo-Fr)."""
    match = re.match(
        r"^\s*([A-Za-z,\-\s]+?)\s+(\d{1,2}:\d{2}(?::\d{2})?)\s*[-–]\s*(\d{1,2}:\d{2}(?::\d{2})?)\s*$",
        line,
    )
    if not match:
        return None

    days = set()
    for token in match.group(1).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            start, _, end = token.partition("-")
            first, last = day_number(start), day_number(end)
            if not first or not last:
                return None
            span = range(first, last + 1) if first <= last else list(range(first, 8)) + list(range(1, last + 1))
            days.update(span)
        else:
            number = day_number(token)
            if not number:
                return None
            days.add(number)

    opens, closes = clock_time(match.group(2)), clock_time(match.group(3))
    if not days or not opens or not closes:
        return None
    return {"days": sorted(days), "opens": opens, "closes": closes}


def opening_hours_line(item):
    """{days, opens, closes} -> "Mo-Fr: 13:00 - 22:00 Uhr"."""
    label = day_range_label(item.get("days") or [])
    opens, closes = item.get("opens"), item.get("closes")
    if not opens or not closes:
        return None
    times = opens + " – " + closes + " Uhr"
    return (label + ": " + times) if label else times


# ------------------------------------------------------------
# Weitere Angaben
# ------------------------------------------------------------
def is_zuerich_com(url):
    return bool(url) and "zuerich.com" in url.lower()


def extract_links(node):
    """(Webseite des Ortes, Detailseite auf zuerich.com). `url` ist je nach
    Eintrag das eine oder das andere - unterschieden wird am Host."""
    website, zuerich_url = None, None
    candidates = []
    for field in ("url", "sameAs", "mainEntityOfPage"):
        value = node.get(field)
        if isinstance(value, (list, tuple)):
            candidates.extend(local_text(v) for v in value)
        else:
            candidates.append(local_text(value))

    for candidate in candidates:
        if not candidate or not candidate.startswith("http"):
            continue
        if is_zuerich_com(candidate):
            zuerich_url = zuerich_url or candidate
        else:
            website = website or candidate
    return website, zuerich_url


def plain_text(value, limit=None):
    """Fliesstext ohne HTML und Entities, optional gekuerzt. Das API liefert
    `description` als HTML-Absatz mit maskierten Umlauten."""
    text = local_text(value)
    if not text:
        return None
    text = html.unescape(text)
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"</p\s*>", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = " ".join(text.split())
    if limit and len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0] + "…"
    return text or None


def extract_description(node):
    """Ausfuehrlicher Beschreibungstext (`description`), sonst der Teaser."""
    return (plain_text(node.get("description"), MAX_DESCRIPTION_CHARS)
            or plain_text(node.get("textTeaser"), MAX_DESCRIPTION_CHARS)
            or plain_text(node.get("disambiguatingDescription"), MAX_DESCRIPTION_CHARS))


def extract_highlights(node):
    """Stichpunkte aus `detailedInformation` (deutsche Liste)."""
    value = node.get("detailedInformation")
    if isinstance(value, dict):
        for language in LANGUAGES:
            candidate = value.get(language)
            if isinstance(candidate, list) and candidate:
                value = candidate
                break
    if not isinstance(value, list):
        single = plain_text(value)
        return [single] if single else []

    items = []
    for item in value:
        text = plain_text(item)
        if text and text not in items:
            items.append(text)
    return items[:MAX_HIGHLIGHTS]


def extract_address(node):
    """Adressblock des API: Strasse, PLZ, Ort und die Kontaktangaben, die dort
    statt auf oberster Ebene stehen."""
    address = node.get("address")
    if isinstance(address, list):
        address = address[0] if address else None
    if not isinstance(address, dict):
        return {}

    street = local_text(address.get("streetAddress"))
    postal = local_text(address.get("postalCode"))
    locality = local_text(address.get("addressLocality"))

    lines = [part for part in (street, " ".join(filter(None, (postal, locality)))) if part]
    return {
        "street_address": street,
        "postal_code": postal,
        "locality": locality,
        "address_line": ", ".join(lines) if lines else None,
        "phone": local_text(address.get("telephone")),
        "email": local_text(address.get("email")),
        "url": local_text(address.get("url")),
    }


def entry_to_place(node, max_images):
    """Ein API-Eintrag, reduziert auf das, was die App braucht. Ohne Name
    oder Koordinaten laesst sich nichts zuordnen - der Rest darf fehlen."""
    lat, lng = entry_coordinates(node)
    name = local_text(node.get("name"))
    if not name or lat is None:
        return None

    opening_hours, opening_hours_spec = extract_opening_hours(node)
    website, zuerich_url = extract_links(node)
    address = extract_address(node)

    # Kontakt und Webseite stehen bei vielen Eintraegen im Adressblock statt
    # auf oberster Ebene - beides pruefen, sonst fehlen sie in der App.
    address_url = address.get("url")
    if address_url and address_url.startswith("http"):
        if is_zuerich_com(address_url):
            zuerich_url = zuerich_url or address_url
        else:
            website = website or address_url

    place = {
        "identifier": entry_key(node),
        "name": name,
        "latitude": lat,
        "longitude": lng,
        "images": extract_images(node, max_images),
        "opening_hours": opening_hours,
        "opening_hours_spec": opening_hours_spec,
        "phone": local_text(node.get("telephone")) or address.get("phone"),
        "email": local_text(node.get("email")) or address.get("email"),
        "website": website,
        "zuerich_url": zuerich_url,
        "description": extract_description(node),
        "summary": plain_text(node.get("disambiguatingDescription")),
        "teaser": plain_text(node.get("textTeaser")),
        "highlights": extract_highlights(node),
        "price_range": (local_text(node.get("priceRange"))
                        or local_text(node.get("price"))),
        "street_address": address.get("street_address"),
        "postal_code": address.get("postal_code"),
        "locality": address.get("locality"),
        "address_line": address.get("address_line"),
        "updated_at": local_text(node.get("dateModified")),
    }

    # Ein Eintrag ohne jede verwertbare Angabe bringt dem POI nichts.
    return place if place_payload(place) else None


def place_payload(place):
    """Die Felder, die dieser Import in accessibility_details schreibt -
    leere Angaben bleiben weg, damit die App Platzhalter zeigen kann."""
    payload = {}
    if place["images"]:
        payload["images"] = place["images"]
        payload["image_source"] = IMAGE_SOURCE
    if place["opening_hours"]:
        payload["opening_hours"] = place["opening_hours"]
    if place["opening_hours_spec"]:
        payload["opening_hours_spec"] = place["opening_hours_spec"]
    if place.get("highlights"):
        payload["highlights"] = place["highlights"]
    for field in ("phone", "email", "website", "description", "summary",
                  "teaser", "price_range", "zuerich_url", "street_address",
                  "postal_code", "locality", "address_line", "updated_at"):
        if place.get(field):
            payload[field] = place[field]

    if payload:
        payload["zuerich_name"] = place["name"]
        payload["info_source"] = INFO_SOURCE
    return payload


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
            place = best["place"]
            matches.append({
                "poi_id": poi.get("id"),
                "poi_source": poi.get("source"),
                "poi_source_id": poi.get("source_id"),
                "poi_name": poi["name"],
                "matched_name": place["name"],
                "distance_m": round(best["distance_m"], 1),
                "name_ratio": round(best["ratio"], 3),
                "identifier": place["identifier"],
                "payload": place_payload(place),
                "accessibility_details": poi.get("accessibility_details") or {},
            })
    return matches


def print_coverage(pois, matches):
    """Wie viele POIs das API kennt und was es je Feld beisteuert - die
    Abdeckung gehoert in die Arbeit und erklaert die Platzhalter in der App."""
    total, hit = len(pois), len(matches)
    percent = (100.0 * hit / total) if total else 0.0
    print("OK " + str(hit) + " von " + str(total) + " POIs im API gefunden ("
          + "{:.0f}".format(percent) + " %)")
    for key, label in (("images", "mit Fotos"),
                       ("opening_hours", "mit Oeffnungszeiten"),
                       ("phone", "mit Telefon"),
                       ("website", "mit Webseite"),
                       ("description", "mit Beschreibung")):
        count = sum(1 for m in matches if m["payload"].get(key))
        print("   " + label.ljust(22) + str(count))
    print("   " + "ohne Treffer".ljust(22) + str(total - hit)
          + " (die App zeigt dort Platzhalter)")


def payload_summary(payload):
    """Kurzform fuer die Konsole: was dieser Treffer beisteuert."""
    parts = []
    if payload.get("images"):
        parts.append(str(len(payload["images"])) + " Bilder")
    if payload.get("opening_hours"):
        parts.append("Zeiten")
    if payload.get("phone"):
        parts.append("Telefon")
    if payload.get("website"):
        parts.append("Web")
    if payload.get("description"):
        parts.append("Text")
    return ", ".join(parts) if parts else "-"


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
    """accessibility_details des POI plus die Angaben aus dem API."""
    details = dict(match["accessibility_details"])
    details.update(match["payload"])
    return details


def write_sql(matches, path):
    """Idempotentes SQL fuer den Supabase-SQL-Editor (ohne Service-Key).
    `||` merged in das bestehende JSONB, alle anderen Felder bleiben."""
    lines = [
        "-- Omina - POI-Angaben aus dem Zuerich-Tourismus-API",
        "-- Quelle: " + BASE_URL + DATA_PATH + " (Open Data 2.0, " + INFO_SOURCE + ")",
        "-- Erzeugt: " + datetime.now().isoformat(timespec="seconds"),
        "-- Setzt in accessibility_details: images, opening_hours, phone,",
        "-- website, description ... Mehrfaches Ausfuehren ueberschreibt",
        "-- dieselben Felder und ist damit idempotent.",
        "",
        "BEGIN;",
        "",
    ]

    written = 0
    for match in matches:
        patch = json.dumps(match["payload"], ensure_ascii=False).replace("'", "''")
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


def update_seed_file(matches, path):
    """Denselben Stand in den Offline-Seed der App schreiben (seed_pois.json),
    damit Simulator und Feldtest ohne Netz dieselben Angaben zeigen.
    Zugeordnet wird ueber source_id, sonst ueber Name und Koordinaten."""
    with open(path, "r", encoding="utf-8") as handle:
        seeds = json.load(handle)

    by_source_id = {}
    by_name = {}
    for seed in seeds:
        if seed.get("source_id"):
            by_source_id[str(seed["source_id"])] = seed
        by_name.setdefault(seed.get("name"), []).append(seed)

    updated = 0
    for match in matches:
        seed = None
        if match.get("poi_source_id"):
            seed = by_source_id.get(str(match["poi_source_id"]))
        if seed is None:
            # Nur wenn der Name im Seed eindeutig ist - sonst liesse sich
            # nicht sagen, welcher der gleichnamigen Orte gemeint ist.
            candidates = by_name.get(match["poi_name"]) or []
            seed = candidates[0] if len(candidates) == 1 else None
        if seed is None:
            continue
        details = dict(seed.get("accessibility_details") or {})
        details.update(match["payload"])
        seed["accessibility_details"] = details
        updated += 1

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(seeds, handle, indent=2, ensure_ascii=False)
    return updated


def update_supabase(client, matches):
    print("\nSchreibe Angaben zu " + str(len(matches)) + " POIs in Supabase...")
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
        description="POIs gegen das Zuerich-Tourismus-API pruefen und um Fotos, "
                    "Oeffnungszeiten und Kontaktangaben ergaenzen")
    parser.add_argument("--dry-run", action="store_true",
                        help="nur Zuordnung zeigen, nichts schreiben")
    parser.add_argument("--pois-file",
                        help="POIs aus einem Import-Backup statt aus Supabase lesen "
                             "(Vorschau ohne Zugangsdaten)")
    parser.add_argument("--seed-file",
                        help="zusaetzlich den Offline-Seed der App aktualisieren "
                             "(Omina/Omina/Seed/seed_pois.json)")
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
    print("Zuerich-Tourismus Import - Omina")
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
    print("OK " + str(len(places)) + " Eintraege mit Koordinaten und Angaben "
          + "(" + str(sum(len(p["images"]) for p in places)) + " Bilder, "
          + str(sum(1 for p in places if p["opening_hours"])) + " mit Oeffnungszeiten)")

    if not places:
        print("Keine verwertbaren Eintraege gefunden - Abbruch.")
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

    # 4. Zuordnung: fuer jeden POI pruefen, ob es ihn im API gibt
    print("\nPruefe jeden POI gegen das API (max. " + str(args.max_distance_m) + " m)...")
    matches = match_pois(pois, places, args.max_distance_m)
    print_coverage(pois, matches)

    for match in matches[:15]:
        print("  + " + match["poi_name"] + "  <-  " + match["matched_name"]
              + "  (" + str(match["distance_m"]) + " m, "
              + str(int(match["name_ratio"] * 100)) + "% Name: "
              + payload_summary(match["payload"]) + ")")
    if len(matches) > 15:
        print("  ... und " + str(len(matches) - 15) + " weitere")

    if not matches:
        print("Keine Zuordnung moeglich - nichts zu schreiben.")
        return

    # 5. Backup + SQL
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = export_path("poi_zurich_tourism_" + stamp + ".json")
    with open(backup_file, "w", encoding="utf-8") as handle:
        json.dump([{k: v for k, v in m.items() if k != "accessibility_details"}
                   for m in matches], handle, indent=2, ensure_ascii=False)
    print("\nOK Backup gespeichert: " + backup_file)

    sql_file = export_path("poi_zurich_tourism_" + stamp + ".sql")
    print("OK SQL geschrieben: " + sql_file + " ("
          + str(write_sql(matches, sql_file)) + " UPDATEs)")

    # 6. Schreiben
    if args.dry_run:
        print("\n--dry-run: nichts geschrieben.")
        return

    if args.seed_file:
        print("OK Offline-Seed aktualisiert: " + args.seed_file + " ("
              + str(update_seed_file(matches, args.seed_file)) + " POIs)")

    if args.pois_file:
        print("\nOhne POI-IDs (--pois-file) wird nicht in Supabase geschrieben - "
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