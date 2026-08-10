// participants.ts
// Tabelle der Testpersonen mit aufklappbarem Onboarding-Profil.

import { el } from "../lib/dom.ts";
import type { ParticipantStats } from "../lib/analytics.ts";
import type { OnboardingProfile } from "../lib/types.ts";
import {
  companionLabel,
  formatDateTime,
  formatDuration,
  formatNumber,
  mobilityLabel,
  surfaceLabel,
  wheelchairLabel,
} from "../lib/format.ts";

const COLUMNS = [
  "Testperson",
  "Rollstuhltyp",
  "Verlauf",
  "Testläufe",
  "Ereignisse",
  "Erste Aktivität",
  "Dauer",
  "Gerät",
] as const;

/**
 * Status-Kennzeichen, vierfach codiert (Styleguide §2.3): Farbe, Form,
 * Symbol und Text tragen dieselbe Aussage – die Tabelle bleibt in Graustufen
 * und bei Farbfehlsichtigkeit lesbar.
 */
function badge(done: boolean, doneText: string, openText: string): HTMLElement {
  return el(
    "span",
    { class: done ? "badge badge--open" : "badge badge--limited" },
    [
      el("span", { class: "badge__symbol", "aria-hidden": "true" }, done ? "✓" : "!"),
      done ? doneText : openText,
    ],
  );
}

/** Ein Feld der Profil-Liste; leere Werte werden übersprungen. */
function field(term: string, value: string | null): HTMLElement | null {
  if (value === null || value === "" || value === "–") return null;
  return el("div", {}, [el("dt", {}, term), el("dd", {}, value)]);
}

function profileList(profile: OnboardingProfile | null): HTMLElement {
  if (profile === null) {
    return el(
      "p",
      { class: "section__note" },
      "Für diese Testperson wurden keine Onboarding-Daten gespeichert – vermutlich wurde das Onboarding abgebrochen.",
    );
  }

  const cm = (value: number | undefined): string | null =>
    value === undefined ? null : `${formatNumber(value)} cm`;

  const fields = [
    field("Mobilitätskategorie", mobilityLabel(profile.mobilityCategory)),
    field("Rollstuhltyp", wheelchairLabel(profile.wheelchairType)),
    field("Breite", cm(profile.widthCm)),
    field("Länge", cm(profile.lengthCm)),
    field("Körpergrösse", cm(profile.heightCm)),
    field("Sitzhöhe", cm(profile.seatHeightCm)),
    field(
      "Gewicht",
      profile.weightKg === undefined
        ? null
        : `${formatNumber(profile.weightKg)} kg`,
    ),
    field("Manövrier-Spielraum", cm(profile.maneuverBufferCm)),
    field(
      "Max. Steigung",
      profile.maxIncline === undefined
        ? null
        : `${formatNumber(profile.maxIncline)} %`,
    ),
    field(
      "Max. Bordstein",
      profile.maxCurbHeight === undefined
        ? null
        : `${formatNumber(profile.maxCurbHeight)} cm`,
    ),
    field("Oberflächen-Toleranz", surfaceLabel(profile.surfaceTolerance)),
    field(
      "Reisegeschwindigkeit",
      profile.travelSpeedKmh === undefined
        ? null
        : `${formatNumber(profile.travelSpeedKmh)} km/h`,
    ),
    field("Begleitung", companionLabel(profile.companionStatus)),
    field(
      "Begleitung heute",
      profile.companionTodayOverride === undefined
        ? null
        : profile.companionTodayOverride
          ? "ja"
          : "nein",
    ),
    field(
      "Nasse Bedingungen",
      profile.wetConditionsToday === undefined
        ? null
        : profile.wetConditionsToday
          ? "ja"
          : "nein",
    ),
    field(
      "Wenig Energie",
      profile.lowEnergyToday === undefined
        ? null
        : profile.lowEnergyToday
          ? "ja"
          : "nein",
    ),
    field(
      "Eurokey",
      profile.hasEurokey === undefined
        ? null
        : profile.hasEurokey
          ? "vorhanden"
          : "nicht vorhanden",
    ),
  ].filter((node): node is HTMLElement => node !== null);

  return el("dl", { class: "profile-grid" }, fields);
}

export function participantsTable(
  stats: readonly ParticipantStats[],
): HTMLElement {
  if (stats.length === 0) {
    return el("div", { class: "state" }, [
      el("p", { class: "state__title" }, "Keine Testpersonen"),
      el(
        "p",
        {},
        "Für den gewählten Testtag liegen keine Einträge in test_participants vor.",
      ),
    ]);
  }

  const body = el("tbody");

  for (const entry of stats) {
    const { participant } = entry;

    body.appendChild(
      el("tr", {}, [
        el("td", {}, [
          el("strong", {}, participant.display_name),
          el("br"),
          el("span", { class: "section__note" }, participant.test_profile_key),
        ]),
        el("td", {}, wheelchairLabel(participant.profile?.wheelchairType)),
        el("td", {}, [
          badge(entry.completedOnboarding, "Onboarding fertig", "Onboarding offen"),
          " ",
          badge(entry.endedTest, "Test beendet", "Test offen"),
        ]),
        el("td", { class: "td--num" }, formatNumber(entry.sessions)),
        el("td", { class: "td--num" }, formatNumber(entry.events)),
        el(
          "td",
          {},
          entry.firstActivity === null
            ? "–"
            : formatDateTime(entry.firstActivity.toISOString()),
        ),
        el("td", {}, formatDuration(entry.durationMs)),
        el("td", { class: "section__note" }, [
          participant.device_model ?? "–",
          participant.app_version === null
            ? null
            : el("span", {}, ` · App ${participant.app_version}`),
        ]),
      ]),
    );

    body.appendChild(
      el("tr", {}, [
        el(
          "td",
          { colspan: COLUMNS.length },
          el("details", { class: "details" }, [
            el(
              "summary",
              { class: "details__summary" },
              `Onboarding-Profil von ${participant.display_name}`,
            ),
            profileList(participant.profile),
          ]),
        ),
      ]),
    );
  }

  const table = el("table", { class: "table" }, [
    el(
      "caption",
      {},
      "Eine Zeile pro Testperson, darunter das im Onboarding erfasste Profil.",
    ),
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