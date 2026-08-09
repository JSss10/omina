#!/usr/bin/env python3
"""
ginto API Import Script - Omina
Laedt alle verfuegbaren POIs aus der ginto GraphQL API fuer die ganze
Schweiz und schreibt sie in die Supabase poi_accessibility Tabelle.

Verwendung:
    python3 import_ginto.py

Voraussetzungen:
    pip3 install requests supabase
"""

import os
import sys
import json
import requests
from datetime import datetime
from supabase import create_client, Client

# ============================================================
# KONFIGURATION
# ============================================================
GINTO_API_KEY = os.getenv("GINTO_API_KEY", "")
GINTO_ENDPOINT = "https://api.ginto.guide/graphql"

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

# Ganze Schweiz: geografischer Mittelpunkt (Aelggi-Alp) mit einem Radius,
# der das ganze Land inkl. Rand abdeckt. Die ginto-API paginiert die
# Ergebnisse, deshalb werden mit diesem einen Suchmittelpunkt alle POIs
# der Schweiz geladen.
CH_LAT = 46.8011
CH_LNG = 8.2266
RADIUS_KM = 300

# Rating Profile IDs
PROFILE_MANUAL = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzc4"
PROFILE_POWER = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzc5"
PROFILE_SCEWO = "Z2lkOi8vcmFpbHMtYXBwL1JhdGluZ1Byb2ZpbGVzOjpSYXRpbmdQcm9maWxlLzM5NTE"


# ============================================================
# GraphQL Query mit Paginierung
# ============================================================
# Zusatzfelder pro Eintrag: laut Schema-Introspektion (Entry) gibt es
# mainImage (Hauptbild) und url (ginto-Detailseite). mainImage.url verlangt
# ein imageSize-Argument; da die Enum-Werte nicht dokumentiert sind, werden
# gaengige Werte durchprobiert (die erste funktionierende Variante gewinnt).
EXTRA_FIELD_VARIANTS = [
    "url mainImage { url(imageSize: MEDIUM) }",
    "url mainImage { url(imageSize: LARGE) }",
    "url mainImage { url(imageSize: SMALL) }",
    "url mainImage { url(imageSize: ORIGINAL) }",
    "url",  # Fallback: nur ginto-Link, ohne Bild
    "",     # Fallback: ohne Bild und Link importieren
]


def build_query(after_cursor=None, extra_fields=""):
    after_clause = ', after: "' + after_cursor + '"' if after_cursor else ""

    return """
    {
      entriesBySearch(lat: """ + str(CH_LAT) + """, lng: """ + str(CH_LNG) + """, query: "", within: """ + str(RADIUS_KM) + """, first: 50""" + after_clause + """) {
        totalCount
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          node {
            id
            name
            position {
              street
              housenumber
              postcode
              city
              lat
              lng
            }
            categories {
              groupKey
              groupName
              key
              name
            }
            manualWheelchair: accessibility(ratingProfileId: \"""" + PROFILE_MANUAL + """\") {
              grade
              conformance
            }
            powerWheelchair: accessibility(ratingProfileId: \"""" + PROFILE_POWER + """\") {
              grade
              conformance
            }
            scewoBro: accessibility(ratingProfileId: \"""" + PROFILE_SCEWO + """\") {
              grade
              conformance
            }
            """ + extra_fields + """
          }
        }
      }
    }
    """


class GintoQueryError(Exception):
    pass


def fetch_ginto_page(after_cursor=None, extra_fields=""):
    headers = {
        "Authorization": "Bearer " + GINTO_API_KEY,
        "Content-Type": "application/json",
        "Accept-Language": "de",
    }

    payload = {"query": build_query(after_cursor, extra_fields)}
    response = requests.post(GINTO_ENDPOINT, json=payload, headers=headers, timeout=60)
    response.raise_for_status()

    data = response.json()
    if "errors" in data:
        raise GintoQueryError(str(data["errors"]))

    return data["data"]["entriesBySearch"]


def resolve_extra_fields():
    """Probiert die Zusatzfeld-Varianten gegen die erste Seite durch."""
    last_error = None
    for variant in EXTRA_FIELD_VARIANTS:
        try:
            fetch_ginto_page(extra_fields=variant)
            if variant:
                print("OK Zusatzfelder im Schema: " + variant)
            else:
                print("WARNUNG: keine Bild-/Link-Felder gefunden - Import ohne Fotos")
            return variant
        except GintoQueryError as e:
            last_error = e
    print("GraphQL Errors: " + str(last_error))
    sys.exit(1)


def fetch_all_pois():
    print("Lade POIs aus ginto API...")

    extra_fields = resolve_extra_fields()

    all_pois = []
    cursor = None
    page = 1

    while True:
        result = fetch_ginto_page(cursor, extra_fields)
        edges = result.get("edges", [])
        all_pois.extend([edge["node"] for edge in edges])
        
        total = result.get("totalCount", 0)
        print("  Seite " + str(page) + ": " + str(len(edges)) + " POIs (total geladen: " + str(len(all_pois)) + "/" + str(total) + ")")
        
        page_info = result.get("pageInfo", {})
        if not page_info.get("hasNextPage"):
            break
        
        cursor = page_info.get("endCursor")
        page += 1
    
    print("OK " + str(len(all_pois)) + " POIs geladen")
    return all_pois


# ============================================================
# DATEN-MAPPING: ginto -> poi_accessibility
# ============================================================
def map_grade_to_status(grade):
    mapping = {
        "COMPLETELY": "yes",
        "PARTIALLY": "limited",
        "BADLY": "no",
    }
    return mapping.get(grade, "unknown")


def ginto_to_poi(node):
    position = node.get("position") or {}
    lat = position.get("lat")
    lng = position.get("lng")
    
    if not lat or not lng:
        return None
    
    street = position.get("street") or ""
    housenumber = position.get("housenumber") or ""
    postcode = position.get("postcode") or ""
    city = position.get("city") or ""
    address = (street + " " + housenumber + ", " + postcode + " " + city).strip(" ,")
    
    categories = node.get("categories") or []
    category = categories[0].get("key") if categories else None
    
    manual = node.get("manualWheelchair") or {}
    power = node.get("powerWheelchair") or {}
    scewo = node.get("scewoBro") or {}
    
    # Bild-URLs: mainImage (aktuelles Schema, ein Hauptbild) bzw.
    # images/photos (Fallback-Varianten) auf eine Liste normalisieren.
    raw_images = node.get("images") or node.get("photos") or []
    main_image = node.get("mainImage")
    if main_image:
        raw_images = [main_image] + list(raw_images)

    images = []
    for image in raw_images:
        url = image.get("url") if isinstance(image, dict) else image
        if url and url not in images:
            images.append(url)

    accessibility_details = {
        "manual": {
            "grade": manual.get("grade"),
            "conformance": manual.get("conformance"),
        },
        "power": {
            "grade": power.get("grade"),
            "conformance": power.get("conformance"),
        },
        "scewo": {
            "grade": scewo.get("grade"),
            "conformance": scewo.get("conformance"),
        },
        "categories": [
            {"groupKey": c.get("groupKey"), "key": c.get("key"), "name": c.get("name")}
            for c in categories
        ],
        "images": images,
        # Link auf die ginto-Detailseite des Eintrags.
        "ginto_url": node.get("url"),
    }
    
    wheelchair_accessible = map_grade_to_status(manual.get("grade", "unknown"))
    
    return {
        "name": node.get("name", "Unbenannt"),
        "category": category,
        "location": "POINT(" + str(lng) + " " + str(lat) + ")",
        "address": address,
        "wheelchair_accessible": wheelchair_accessible,
        "accessibility_details": accessibility_details,
        "source": "ginto",
        "source_id": node.get("id"),
        "last_updated": datetime.now().isoformat(),
    }


# ============================================================
# SUPABASE IMPORT
# ============================================================
def import_to_supabase(pois):
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("WARNUNG: SUPABASE_URL und SUPABASE_SERVICE_KEY muessen gesetzt sein")
        sys.exit(1)
    
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    print("\nSchreibe " + str(len(pois)) + " POIs in Supabase...")
    
    batch_size = 50
    for i in range(0, len(pois), batch_size):
        batch = pois[i:i + batch_size]
        try:
            result = supabase.table("poi_accessibility").insert(batch).execute()
            print("OK Batch " + str(i // batch_size + 1) + ": " + str(len(batch)) + " Eintraege")
        except Exception as e:
            print("FEHLER in Batch " + str(i // batch_size + 1) + ": " + str(e))
    
    print("\nOK Import abgeschlossen!")


# ============================================================
# MAIN
# ============================================================
def main():
    print("=" * 60)
    print("ginto Import - Omina")
    print("Gebiet: ganze Schweiz (" + str(CH_LAT) + ", " + str(CH_LNG) + ")")
    print("Radius: " + str(RADIUS_KM) + "km")
    print("=" * 60)
    
    if not GINTO_API_KEY:
        print("WARNUNG: GINTO_API_KEY muss als Env-Variable gesetzt sein")
        sys.exit(1)
    
    nodes = fetch_all_pois()
    
    print("\nMappe ginto Daten auf Schema...")
    pois = []
    for node in nodes:
        poi = ginto_to_poi(node)
        if poi:
            pois.append(poi)
    
    print("OK " + str(len(pois)) + " POIs gemapped")
    
    grade_counts = {"COMPLETELY": 0, "PARTIALLY": 0, "BADLY": 0, "unknown": 0}
    for poi in pois:
        grade = poi["accessibility_details"]["manual"]["grade"] or "unknown"
        grade_counts[grade] = grade_counts.get(grade, 0) + 1
    
    print("\nZugaenglichkeit (manueller Rollstuhl):")
    print("  - COMPLETELY (gruen):  " + str(grade_counts['COMPLETELY']))
    print("  - PARTIALLY (orange):  " + str(grade_counts['PARTIALLY']))
    print("  - BADLY (rot):         " + str(grade_counts['BADLY']))
    print("  - unknown:             " + str(grade_counts.get('unknown', 0)))
    
    backup_file = "pois_ginto_" + datetime.now().strftime('%Y%m%d_%H%M%S') + ".json"
    with open(backup_file, "w", encoding="utf-8") as f:
        json.dump(pois, f, indent=2, ensure_ascii=False, default=str)
    print("\nOK Backup gespeichert: " + backup_file)
    
    confirm = input("\nIn Supabase importieren? (y/n): ")
    if confirm.lower() == "y":
        import_to_supabase(pois)
    else:
        print("Import abgebrochen.")


if __name__ == "__main__":
    main()