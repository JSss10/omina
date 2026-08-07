// app.ts
// Aufbau und Zustand des Dashboards.

import { supabase } from "./lib/supabase.ts";
import { el, render } from "./lib/dom.ts";
import {
  isResearcher,
  loadEvents,
  loadParticipants,
  loadTestDays,
} from "./lib/data.ts";
import type { EventRow, ParticipantRow, TestDayRow } from "./lib/types.ts";
import {
  countEventNames,
  countScreenViews,
  funnel,
  statsPerParticipant,
  summarise,
} from "./lib/analytics.ts";
import {
  eventLabel,
  formatDecimal,
  formatDuration,
  formatNumber,
  formatTestDay,
  screenLabel,
  wheelchairLabel,
} from "./lib/format.ts";
import { downloadCsv, toCsv } from "./lib/csv.ts";
import { themeToggle } from "./components/theme.ts";
import { kpiGrid } from "./components/kpi.ts";
import { barChart } from "./components/chart.ts";
import { participantsTable } from "./components/participants.ts";
import { eventLog } from "./components/eventLog.ts";

/** Wert des Auswahlfelds, wenn alle Testtage gemeinsam ausgewertet werden. */
const ALL_DAYS = "__all__";
const ALL_PARTICIPANTS = "__all__";

interface State {
  days: TestDayRow[];
  selectedDay: string;
  selectedUser: string;
  participants: ParticipantRow[];
  events: EventRow[];
  loading: boolean;
  error: string | null;
}

const state: State = {
  days: [],
  selectedDay: ALL_DAYS,
  selectedUser: ALL_PARTICIPANTS,
  participants: [],
  events: [],
  loading: true,
  error: null,
};

/** Container, die zwischen den Renderdurchläufen bestehen bleiben. */
let contentRoot: HTMLElement;
let statusRegion: HTMLElement;

// ---------------------------------------------------------------
// Kopfzeile
// ---------------------------------------------------------------

function header(email: string, onSignOut: () => void): HTMLElement {
  const signOut = el(
    "button",
    { class: "btn btn--secondary btn--compact", type: "button" },
    "Abmelden",
  );
  signOut.addEventListener("click", onSignOut);

  return el("header", { class: "app-header" }, [
    el("div", { class: "app-header__titles" }, [
      el("h1", {}, "Feldtest-Auswertung"),
      el(
        "p",
        { class: "app-header__subtitle" },
        "AR-Mikronavigation · Altstadt Zürich",
      ),
    ]),
    el("div", { class: "app-header__actions" }, [
      el("span", { class: "app-header__user" }, email),
      themeToggle(),
      signOut,
    ]),
  ]);
}

// ---------------------------------------------------------------
// Werkzeugleiste
// ---------------------------------------------------------------

function toolbar(): HTMLElement {
  const daySelect = el("select", { class: "select", id: "filter-day" });
  daySelect.appendChild(
    el(
      "option",
      { value: ALL_DAYS },
      `Alle Testtage (${formatNumber(state.days.reduce((sum, day) => sum + Number(day.participant_count), 0))} Testpersonen)`,
    ),
  );
  for (const day of state.days) {
    const option = el(
      "option",
      { value: day.test_day },
      `${formatTestDay(day.test_day)} · ${formatNumber(Number(day.participant_count))} Testpersonen`,
    );
    if (day.test_day === state.selectedDay) option.selected = true;
    daySelect.appendChild(option);
  }
  daySelect.addEventListener("change", () => {
    state.selectedDay = daySelect.value;
    state.selectedUser = ALL_PARTICIPANTS;
    void refresh();
  });

  const userSelect = el("select", { class: "select", id: "filter-user" });
  userSelect.appendChild(
    el("option", { value: ALL_PARTICIPANTS }, "Alle Testpersonen"),
  );
  for (const participant of state.participants) {
    const option = el(
      "option",
      { value: participant.user_id },
      participant.display_name,
    );
    if (participant.user_id === state.selectedUser) option.selected = true;
    userSelect.appendChild(option);
  }
  userSelect.addEventListener("change", () => {
    state.selectedUser = userSelect.value;
    renderContent();
  });

  const reload = el(
    "button",
    { class: "btn btn--quiet btn--compact", type: "button" },
    "Neu laden",
  );
  reload.addEventListener("click", () => void refresh());

  const exportEvents = el(
    "button",
    { class: "btn btn--quiet btn--compact", type: "button" },
    "Ereignisse als CSV",
  );
  exportEvents.addEventListener("click", exportEventsCsv);

  const exportParticipants = el(
    "button",
    { class: "btn btn--quiet btn--compact", type: "button" },
    "Testpersonen als CSV",
  );
  exportParticipants.addEventListener("click", exportParticipantsCsv);

  return el("div", { class: "toolbar card" }, [
    el("div", { class: "field" }, [
      el("label", { class: "field__label", for: "filter-day" }, "Testtag"),
      daySelect,
    ]),
    el("div", { class: "field" }, [
      el("label", { class: "field__label", for: "filter-user" }, "Testperson"),
      userSelect,
    ]),
    el("div", { class: "toolbar__actions" }, [
      reload,
      exportParticipants,
      exportEvents,
    ]),
  ]);
}

// ---------------------------------------------------------------
// CSV-Export
// ---------------------------------------------------------------

function exportSuffix(): string {
  return state.selectedDay === ALL_DAYS ? "alle-testtage" : state.selectedDay;
}

function exportParticipantsCsv(): void {
  const stats = statsPerParticipant(state.participants, state.events);
  const csv = toCsv(
    [
      "display_name",
      "test_profile_key",
      "test_day",
      "wheelchair_type",
      "sessions",
      "events",
      "first_activity",
      "last_activity",
      "duration_seconds",
      "onboarding_completed",
      "test_ended",
      "device_model",
      "app_version",
      "profile_json",
    ],
    stats.map((entry) => [
      entry.participant.display_name,
      entry.participant.test_profile_key,
      entry.participant.test_day,
      entry.participant.profile?.wheelchairType ?? "",
      entry.sessions,
      entry.events,
      entry.firstActivity?.toISOString() ?? "",
      entry.lastActivity?.toISOString() ?? "",
      entry.durationMs === null ? "" : Math.round(entry.durationMs / 1000),
      entry.completedOnboarding ? "ja" : "nein",
      entry.endedTest ? "ja" : "nein",
      entry.participant.device_model ?? "",
      entry.participant.app_version ?? "",
      JSON.stringify(entry.participant.profile ?? {}),
    ]),
  );
  downloadCsv(`testpersonen-${exportSuffix()}.csv`, csv);
}

function exportEventsCsv(): void {
  const nameByUser = new Map(
    state.participants.map((p) => [p.user_id, p.display_name]),
  );
  const csv = toCsv(
    [
      "occurred_at",
      "display_name",
      "test_profile_key",
      "session_id",
      "event_name",
      "screen",
      "properties_json",
    ],
    visibleEvents().map((event) => [
      event.occurred_at,
      nameByUser.get(event.user_id) ?? "",
      event.test_profile_key,
      event.session_id,
      event.event_name,
      event.screen ?? "",
      event.properties === null ? "" : JSON.stringify(event.properties),
    ]),
  );
  downloadCsv(`ereignisse-${exportSuffix()}.csv`, csv);
}

// ---------------------------------------------------------------
// Inhalt
// ---------------------------------------------------------------

function visibleEvents(): EventRow[] {
  if (state.selectedUser === ALL_PARTICIPANTS) return state.events;
  return state.events.filter((event) => event.user_id === state.selectedUser);
}

function visibleParticipants(): ParticipantRow[] {
  if (state.selectedUser === ALL_PARTICIPANTS) return state.participants;
  return state.participants.filter(
    (participant) => participant.user_id === state.selectedUser,
  );
}

function section(
  title: string,
  content: HTMLElement,
  note?: string,
): HTMLElement {
  return el("section", { class: "section" }, [
    el("div", { class: "section__head" }, [
      el("h2", { class: "section__title" }, title),
      note === undefined ? null : el("p", { class: "section__note" }, note),
    ]),
    content,
  ]);
}

function renderContent(): void {
  if (state.loading) {
    render(
      contentRoot,
      el("div", { class: "state" }, [
        el("p", { class: "state__title" }, "Daten werden geladen …"),
      ]),
    );
    return;
  }

  if (state.error !== null) {
    render(
      contentRoot,
      el("div", { class: "form-error", role: "alert" }, state.error),
    );
    return;
  }

  const participants = visibleParticipants();
  const events = visibleEvents();
  const summary = summarise(participants, events);
  const stats = statsPerParticipant(participants, events);

  const kpis = kpiGrid([
    {
      label: "Testpersonen",
      value: formatNumber(summary.participants),
      hint:
        state.selectedDay === ALL_DAYS
          ? "über alle Testtage"
          : formatTestDay(state.selectedDay),
    },
    {
      label: "Testläufe",
      value: formatNumber(summary.sessions),
      hint: "eindeutige session_id",
    },
    {
      label: "Ereignisse",
      value: formatNumber(summary.events),
      hint:
        summary.averageEventsPerParticipant === null
          ? undefined
          : `Ø ${formatDecimal(summary.averageEventsPerParticipant)} pro Testperson`,
    },
    {
      label: "Ø Dauer je Testlauf",
      value: formatDuration(summary.averageSessionMs),
      hint: "erstes bis letztes Ereignis",
    },
    {
      label: "Onboarding abgeschlossen",
      value: `${formatNumber(summary.onboardingCompleted)} / ${formatNumber(summary.participants)}`,
      hint: "Ereignis onboarding_completed",
    },
    {
      label: "Regulär beendet",
      value: `${formatNumber(summary.testsEnded)} / ${formatNumber(summary.participants)}`,
      hint: "Ereignis test_ended",
    },
  ]);

  const screenRows = countScreenViews(events).map((entry) => ({
    label: screenLabel(entry.key),
    value: entry.count,
  }));

  const eventRows = countEventNames(events).map((entry) => ({
    label: eventLabel(entry.key),
    value: entry.count,
  }));

  const funnelRows = funnel(participants, events).map((step) => ({
    label:
      step.key === "participants" ? "Profil ausgewählt" : eventLabel(step.key),
    value: step.reached,
  }));

  const wheelchairRows = (() => {
    const counts = new Map<string, number>();
    for (const participant of participants) {
      const key = wheelchairLabel(participant.profile?.wheelchairType);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    return [...counts.entries()]
      .map(([label, value]) => ({ label, value }))
      .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));
  })();

  render(contentRoot, [
    section("Überblick", kpis),
    section(
      "Nutzung",
      el("div", { class: "chart-grid" }, [
        barChart("Screen-Aufrufe", screenRows, { unit: "×", limit: 12 }),
        barChart("Ereignisse nach Typ", eventRows, { unit: "×", limit: 12 }),
        barChart("Weg durch den Testlauf", funnelRows, {
          unit: ["Person", "Personen"],
        }),
        barChart("Rollstuhltypen der Testpersonen", wheelchairRows, {
          unit: ["Person", "Personen"],
        }),
      ]),
      "Balken zeigen den Anteil am jeweiligen Höchstwert.",
    ),
    section("Testpersonen", participantsTable(stats)),
    section("Interaktionsprotokoll", eventLog(events, participants)),
  ]);

  render(
    statusRegion,
    `${formatNumber(participants.length)} Testpersonen und ${formatNumber(events.length)} Ereignisse geladen.`,
  );
}

// ---------------------------------------------------------------
// Laden
// ---------------------------------------------------------------

async function refresh(): Promise<void> {
  state.loading = true;
  state.error = null;
  renderShell();

  try {
    const day = state.selectedDay === ALL_DAYS ? null : state.selectedDay;
    const participants = await loadParticipants(day);
    const events = await loadEvents(
      participants.map((participant) => participant.user_id),
    );

    state.participants = participants;
    state.events = events;

    if (
      state.selectedUser !== ALL_PARTICIPANTS &&
      !participants.some((p) => p.user_id === state.selectedUser)
    ) {
      state.selectedUser = ALL_PARTICIPANTS;
    }
  } catch (error) {
    state.error =
      error instanceof Error ? error.message : "Unbekannter Fehler beim Laden.";
  } finally {
    state.loading = false;
    renderShell();
  }
}

// ---------------------------------------------------------------
// Zusammenbau
// ---------------------------------------------------------------

let shellRoot: HTMLElement;
let signOutHandler: () => void = () => { };
let currentEmail = "";

function renderShell(): void {
  render(shellRoot, [
    el("a", { class: "skip-link", href: "#inhalt" }, "Zum Inhalt springen"),
    header(currentEmail, signOutHandler),
    el("main", { class: "app-main", id: "inhalt", tabindex: "-1" }, [
      toolbar(),
      statusRegion,
      contentRoot,
    ]),
  ]);
  renderContent();
}

/**
 * Baut das Dashboard in `root` auf. Wird aufgerufen, sobald eine Sitzung
 * besteht.
 */
export async function mountDashboard(
  root: HTMLElement,
  email: string,
  onSignOut: () => void,
): Promise<void> {
  shellRoot = root;
  currentEmail = email;
  signOutHandler = onSignOut;

  contentRoot = el("div", { class: "section" });
  // Änderungen an der Datenlage werden angesagt, ohne den Fokus zu verschieben.
  statusRegion = el("p", {
    class: "visually-hidden",
    role: "status",
    "aria-live": "polite",
  });

  // Ohne Freischaltung liefert die RLS leere Ergebnisse – das muss als
  // fehlender Zugriff erkennbar sein, nicht als leerer Testtag.
  const allowed = await isResearcher();
  if (!allowed) {
    render(root, [
      header(email, onSignOut),
      el("main", { class: "app-main", id: "inhalt" }, [
        el("div", { class: "state" }, [
          el("p", { class: "state__title" }, "Dieses Konto ist nicht freigeschaltet"),
          el(
            "p",
            {},
            "Die Auswertung ist auf Konten beschränkt, die in der Tabelle dashboard_researchers eingetragen sind. Der Eintrag erfolgt im Supabase SQL-Editor – siehe migrations/dashboard_access.sql.",
          ),
        ]),
      ]),
    ]);
    return;
  }

  try {
    state.days = await loadTestDays();
  } catch (error) {
    state.days = [];
    state.error =
      error instanceof Error ? error.message : "Testtage nicht ladbar.";
  }

  // Standard: der jüngste Testtag – nicht alle auf einmal.
  const latest = state.days[0];
  if (latest !== undefined) {
    state.selectedDay = latest.test_day;
  }

  await refresh();
}

export function signOut(): Promise<void> {
  return supabase.auth.signOut().then(() => undefined);
}