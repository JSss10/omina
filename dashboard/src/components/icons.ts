// icons.ts
// Die wenigen Symbole des Dashboards als Inline-SVG.
//
// Die App zeichnet ihre Symbole mit SF Symbols; im Browser steht diese
// Bibliothek nicht zur Verfügung. Nachgezeichnet sind deshalb genau die
// Symbole, die im Entwurf vorkommen: das Auge am Passwortfeld
// (AppTextField.swift) und das Warndreieck der Fehlermeldung
// (SignInView.swift).
//
// Symbole sind hier immer Beiwerk: Jede Stelle, an der eines steht, trägt
// die Aussage zusätzlich als Text. Sie sind deshalb `aria-hidden` – die
// Bedeutung hängt nie am Bild allein (WCAG 1.1.1).

import { svg } from "../lib/dom.ts";
import type { Child } from "../lib/dom.ts";

export type IconName = "eye" | "eye-off" | "warning";

const PATHS: Record<IconName, readonly string[]> = {
  // Auge: Passwort ist verdeckt, ein Klick zeigt es.
  eye: ["M2 12c2.7-4 6.1-6 10-6s7.3 2 10 6c-2.7 4-6.1 6-10 6s-7.3-2-10-6Z", "M12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5Z"],
  // Durchgestrichenes Auge: Passwort ist sichtbar, ein Klick verdeckt es.
  "eye-off": [
    "M3 3l18 18",
    "M10.6 6.2A9.6 9.6 0 0 1 12 6c3.9 0 7.3 2 10 6a17 17 0 0 1-3.3 3.8",
    "M6.6 8.2A17 17 0 0 0 2 12c2.7 4 6.1 6 10 6a9.4 9.4 0 0 0 3.6-.7",
  ],
  // Warndreieck der Fehlermeldung.
  warning: ["M12 3.6 22.2 20.4H1.8L12 3.6Z", "M12 9.6v4.2", "M12 17.2h.01"],
};

/**
 * Liefert das Symbol als SVG-Element. Grösse und Farbe kommen aus der
 * Klasse `.icon` in app.css – das Symbol erbt die Schriftfarbe.
 */
export function icon(name: IconName): SVGElement {
  const children: Child[] = PATHS[name].map((d) => svg("path", { d }));

  return svg(
    "svg",
    {
      class: "icon",
      viewBox: "0 0 24 24",
      "aria-hidden": "true",
      focusable: "false",
    },
    children,
  );
}