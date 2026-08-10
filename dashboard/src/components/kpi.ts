// kpi.ts
// Kennzahlen-Kacheln.
//
// Als Liste ausgezeichnet, damit Screenreader die Anzahl ansagen und die
// Kacheln einzeln ansteuerbar sind. Beschriftung und Wert stehen in dieser
// Reihenfolge im DOM – vorgelesen wird «Testpersonen: 6», nicht «6».

import { el } from "../lib/dom.ts";

export interface Kpi {
  label: string;
  value: string;
  hint?: string | undefined;
}

export function kpiGrid(items: readonly Kpi[]): HTMLElement {
  return el(
    "ul",
    { class: "kpi-grid" },
    items.map((item) =>
      el("li", { class: "kpi" }, [
        el("span", { class: "kpi__label" }, item.label),
        el("span", { class: "kpi__value" }, item.value),
        item.hint !== undefined && item.hint !== ""
          ? el("span", { class: "kpi__hint" }, item.hint)
          : null,
      ]),
    ),
  );
}