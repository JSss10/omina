# Drittanbieter-Komponenten und Datenquellen

Der eigene Code von Omina steht unter der proprietären Lizenz in [LICENSE](LICENSE).
Die hier aufgeführten Bestandteile stammen von Dritten und behalten ihre
eigenen Bedingungen – diese gelten unabhängig von der Omina-Lizenz weiter.

## Software-Abhängigkeiten

| Komponente                                                              | Lizenz | Verwendung                              |
| ----------------------------------------------------------------------- | ------ | --------------------------------------- |
| [supabase-swift](https://github.com/supabase/supabase-swift)            | MIT    | Auth, PostgREST-RPCs, Storage           |
| Apple SDKs (SwiftUI, MapKit, ARKit, RealityKit, CoreLocation, CoreMotion) | Apple Developer Program License Agreement | Plattform-Frameworks |

## Daten- und Dienstquellen

| Quelle                          | Lizenz / Bedingungen                        | Verwendung in Omina                                                   |
| ------------------------------- | ------------------------------------------- | --------------------------------------------------------------------- |
| OpenStreetMap (Overpass API)    | ODbL 1.0, © OpenStreetMap-Mitwirkende       | Barrieren (Bordsteine, Treppen, Steigungen, Oberflächen, Engstellen)  |
| OpenRouteService                | ODbL (Daten) / ORS-Nutzungsbedingungen      | Alternativroute um eine einzelne Barriere (`avoid_polygons`)          |
| ginto guide AG                  | Nutzungsbedingungen ginto                   | POI-Zugänglichkeit je Rollstuhltyp                                    |
| Zürich Tourismus, Open Data 2.0 | Open Data, Quellennennung verpflichtend     | POI-Fotos, Öffnungszeiten, Kontakt, Kurzbeschreibung                  |
| Wheelmap                        | CC BY-SA 4.0                                | `wheelchair=yes/limited/no` je POI                                    |
| Open-Meteo                      | CC BY 4.0                                   | Wetter für die Tagesform-Anpassung                                    |
| Apple Maps / MapKit             | Apple-Nutzungsbedingungen                   | Karte, Fussgängerroute, Apple-eigene POIs                             |

Die verlangten Quellennennungen erscheinen in der App: bei den Fotos und den
übernommenen Angaben im POI-Detail sowie unter **Profil → Über Omina**.

## Hinweis zur Weiterverwertung

ODbL (OpenStreetMap) und CC BY-SA (Wheelmap) sind **Share-alike**-Lizenzen. Sie
betreffen nicht den Programmcode, wohl aber abgeleitete Datenbanken. Wer die
importierten Barrieren- und POI-Datenbestände über eine reine Nutzung hinaus
weitergibt – etwa als Datenbank-Dump in einem kommerziellen Produkt –, muss die
Share-alike-Pflichten prüfen. Für eine spätere Kommerzialisierung ist das der
Punkt, an dem eine juristische Einschätzung sinnvoll ist; der eigene Code ist
davon nicht betroffen.
