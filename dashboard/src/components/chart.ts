// chart.ts
// Balkendiagramm ohne Fremdbibliothek.
//
// Der Balken ist reine Dekoration (`aria-hidden`); Beschriftung und Wert
// stehen als Text daneben. Damit ist die Darstellung nicht auf Farbe
// angewiesen (WCAG 1.4.1) und braucht keine Textalternative – die Daten
// selbst sind der Inhalt (WCAG 1.1.1).

import { el } from "../lib/dom.ts";
import { formatNumber } from "../lib/format.ts";

export interface ChartRow {
  label: string;
  value: number;
}

export interface ChartOptions {
  /** Wird statt der Liste gezeigt, wenn keine Daten vorliegen. */
  emptyMessage?: string;
  /** Nur die N häufigsten Zeilen zeigen. */
  limit?: number;
  /**
   * Einheit hinter dem Wert. Als Paar `[Einzahl, Mehrzahl]` angeben, wo die
   * Zahl mitbeugt – sonst steht bei einem Treffer «1 Personen».
   */
  unit?: string | readonly [singular: string, plural: string];
}

function unitFor(
  unit: ChartOptions["unit"],
  value: number,
): string | null {
  if (unit === undefined) return null;
  if (typeof unit === "string") return unit;
  return value === 1 ? unit[0] : unit[1];
}

export function barChart(
  title: string,
  rows: readonly ChartRow[],
  options: ChartOptions = {},
): HTMLElement {
  const {
    emptyMessage = "Für diese Auswahl liegen keine Daten vor.",
    limit,
    unit,
  } = options;

  const shown = limit === undefined ? rows : rows.slice(0, limit);
  const max = shown.reduce((peak, row) => Math.max(peak, row.value), 0);

  const heading = el("h3", { class: "chart__title" }, title);

  if (shown.length === 0) {
    return el("section", { class: "chart card" }, [
      heading,
      el("p", { class: "section__note" }, emptyMessage),
    ]);
  }

  const list = el(
    "ul",
    { class: "chart__rows" },
    shown.map((row) => {
      // Bei max = 0 sind alle Werte 0 – dann bleibt jeder Balken leer.
      const share = max > 0 ? (row.value / max) * 100 : 0;
      const bar = el("div", { class: "chart__bar" });
      bar.style.width = `${share}%`;

      const suffix = unitFor(unit, row.value);

      return el("li", { class: "chart__row" }, [
        el("span", { class: "chart__label" }, row.label),
        el("div", { class: "chart__track", "aria-hidden": "true" }, bar),
        el(
          "span",
          { class: "chart__value" },
          suffix === null
            ? formatNumber(row.value)
            : `${formatNumber(row.value)} ${suffix}`,
        ),
      ]);
    }),
  );

  const note =
    limit !== undefined && rows.length > limit
      ? el(
        "p",
        { class: "section__note" },
        `Zeigt die ${limit} häufigsten von ${formatNumber(rows.length)} Einträgen.`,
      )
      : null;

  return el("section", { class: "chart card" }, [heading, list, note]);
}