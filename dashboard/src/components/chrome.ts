// chrome.ts
// Der gemeinsame Rahmen aller Screens – Web-Fassung von
// BrandAccentBar.swift und AuthHeader.swift.
//
// In der App tragen alle Screens ohne Navigationsleiste dieselbe violette
// Akzentleiste unter der Statusleiste und darunter den Titel im
// Markenviolett mit einer erklärenden Zeile. Das Dashboard übernimmt beides,
// damit Anmeldung, Auswertung und Zustands-Screens denselben Anfang haben.

import { el } from "../lib/dom.ts";

/**
 * Die violette Leiste am oberen Rand. Rein dekorativ – sie zeigt keinen
 * Fortschritt und bleibt für Screenreader unsichtbar.
 */
export function brandBar(): HTMLElement {
  return el("div", { class: "brand-bar", "aria-hidden": "true" });
}

/**
 * Grosser Titel im Markenviolett mit erklärender Zeile darunter.
 * `subtitleId` verknüpft die Zeile bei Bedarf mit einem Formularfeld.
 */
export function authHeader(
  title: string,
  subtitle: string,
  subtitleId?: string,
): HTMLElement {
  return el("div", { class: "auth-header" }, [
    el("h1", { class: "auth-header__title" }, title),
    el(
      "p",
      { class: "auth-header__subtitle", id: subtitleId },
      subtitle,
    ),
  ]);
}