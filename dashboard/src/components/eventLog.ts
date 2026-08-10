// eventLog.ts
// Chronologisches Protokoll aller Interaktionen.
//
// Die Liste kann pro Testtag in die Tausende gehen. Gerendert wird deshalb
// nur ein Ausschnitt; der vollständige Datensatz geht über den CSV-Export.

import { el } from "../lib/dom.ts";
import type { EventRow, ParticipantRow } from "../lib/types.ts";
import {
  eventLabel,
  formatNumber,
  formatProperties,
  formatTime,
  screenLabel,
} from "../lib/format.ts";

const COLUMNS = ["Zeit", "Testperson", "Ereignis", "Screen", "Details"] as const;

export const EVENT_LOG_LIMIT = 200;

export function eventLog(
  events: readonly EventRow[],
  participants: readonly ParticipantRow[],
): HTMLElement {
  if (events.length === 0) {
    return el("div", { class: "state" }, [
      el("p", { class: "state__title" }, "Keine Ereignisse"),
      el(
        "p",
        {},
        "Für die gewählten Filter liegen keine Einträge in test_events vor.",
      ),
    ]);
  }

  const nameByUser = new Map(
    participants.map((participant) => [
      participant.user_id,
      participant.display_name,
    ]),
  );

  // Neueste zuerst – beim Durchsehen interessiert meist das Ende eines Laufs.
  const sorted = [...events].sort((a, b) =>
    b.occurred_at.localeCompare(a.occurred_at),
  );
  const shown = sorted.slice(0, EVENT_LOG_LIMIT);

  const body = el(
    "tbody",
    {},
    shown.map((event) =>
      el("tr", {}, [
        el("td", { class: "td--mono" }, formatTime(event.occurred_at)),
        el(
          "td",
          {},
          nameByUser.get(event.user_id) ?? event.test_profile_key,
        ),
        el("td", {}, eventLabel(event.event_name)),
        el("td", {}, event.screen === null ? "–" : screenLabel(event.screen)),
        el(
          "td",
          { class: "section__note" },
          formatProperties(event.properties) || "–",
        ),
      ]),
    ),
  );

  const caption =
    events.length > EVENT_LOG_LIMIT
      ? `Neueste ${formatNumber(EVENT_LOG_LIMIT)} von ${formatNumber(events.length)} Ereignissen. Der vollständige Datensatz steht im CSV-Export.`
      : `${formatNumber(events.length)} Ereignisse, neueste zuerst.`;

  const table = el("table", { class: "table" }, [
    el("caption", {}, caption),
    el(
      "thead",
      {},
      el(
        "tr",
        {},
        COLUMNS.map((name) => el("th", { scope: "col" }, name)),
      ),
    ),
    body,
  ]);

  return el("div", { class: "table-scroll" }, table);
}