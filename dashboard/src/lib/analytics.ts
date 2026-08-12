// analytics.ts
// Auswertung der Feldtest-Rohdaten.
//
// Bewusst reine Funktionen ohne DOM und ohne Netzwerk: die Aggregation ist
// der inhaltliche Kern des Dashboards und soll ohne Browser testbar sein
// (siehe analytics.test.ts).

import type { EventRow, ParticipantRow } from "./types.ts";

/** Kennzahlen über einen Testtag (oder alle Tage zusammen). */
export interface Summary {
  participants: number;
  sessions: number;
  events: number;
  /** Mittlere Dauer eines Testlaufs in Millisekunden. */
  averageSessionMs: number | null;
  /** Mittlere Anzahl Ereignisse pro Testperson. */
  averageEventsPerParticipant: number | null;
  /** Testpersonen, die das Onboarding abgeschlossen haben. */
  onboardingCompleted: number;
  /** Testpersonen, deren Testlauf regulär beendet wurde. */
  testsEnded: number;
}

/** Ein Eintrag einer Häufigkeitsauswertung, absteigend sortiert. */
export interface CountEntry {
  key: string;
  count: number;
}

/** Kennzahlen zu einer einzelnen Testperson. */
export interface ParticipantStats {
  participant: ParticipantRow;
  sessions: number;
  events: number;
  firstActivity: Date | null;
  lastActivity: Date | null;
  /** Zeit zwischen erstem und letztem Ereignis. */
  durationMs: number | null;
  completedOnboarding: boolean;
  endedTest: boolean;
}

export const EVENT_ONBOARDING_COMPLETED = "onboarding_completed";
export const EVENT_TEST_ENDED = "test_ended";
export const EVENT_SCREEN_VIEW = "screen_view";

/**
 * Gruppiert Ereignisse nach einem Schlüssel. Ereignisse ohne Schlüssel
 * (Selektor gibt `null` zurück) fallen heraus.
 */
export function countBy(
  events: readonly EventRow[],
  selector: (event: EventRow) => string | null,
): CountEntry[] {
  const counts = new Map<string, number>();
  for (const event of events) {
    const key = selector(event);
    if (key === null || key === "") continue;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([key, count]) => ({ key, count }))
    // Gleich häufige Einträge alphabetisch, damit die Reihenfolge zwischen
    // zwei Aufrufen stabil bleibt und die Liste nicht springt.
    .sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));
}

/** Screen-Aufrufe nach Screen. */
export function countScreenViews(events: readonly EventRow[]): CountEntry[] {
  return countBy(events, (event) =>
    event.event_name === EVENT_SCREEN_VIEW ? event.screen : null,
  );
}

/** Alle Ereignisse nach Ereignisname. */
export function countEventNames(events: readonly EventRow[]): CountEntry[] {
  return countBy(events, (event) => event.event_name);
}

/**
 * Dauer je Testlauf (`session_id`): Abstand zwischen erstem und letztem
 * Ereignis. Läufe mit nur einem Ereignis ergeben 0 und zählen mit – sie sind
 * ein echtes Ergebnis (Abbruch), kein fehlender Wert.
 */
export function sessionDurations(
  events: readonly EventRow[],
): Map<string, number> {
  const bounds = new Map<string, { min: number; max: number }>();
  for (const event of events) {
    const time = new Date(event.occurred_at).getTime();
    if (Number.isNaN(time)) continue;
    const current = bounds.get(event.session_id);
    if (current === undefined) {
      bounds.set(event.session_id, { min: time, max: time });
    } else {
      current.min = Math.min(current.min, time);
      current.max = Math.max(current.max, time);
    }
  }
  const durations = new Map<string, number>();
  for (const [sessionId, { min, max }] of bounds) {
    durations.set(sessionId, max - min);
  }
  return durations;
}

/** Anzahl Testpersonen, von denen mindestens ein Ereignis dieses Namens vorliegt. */
function participantsWithEvent(
  events: readonly EventRow[],
  eventName: string,
): number {
  const users = new Set<string>();
  for (const event of events) {
    if (event.event_name === eventName) users.add(event.user_id);
  }
  return users.size;
}

export function summarise(
  participants: readonly ParticipantRow[],
  events: readonly EventRow[],
): Summary {
  const durations = [...sessionDurations(events).values()];
  const averageSessionMs =
    durations.length > 0
      ? durations.reduce((sum, value) => sum + value, 0) / durations.length
      : null;

  return {
    participants: participants.length,
    sessions: durations.length,
    events: events.length,
    averageSessionMs,
    averageEventsPerParticipant:
      participants.length > 0 ? events.length / participants.length : null,
    onboardingCompleted: participantsWithEvent(
      events,
      EVENT_ONBOARDING_COMPLETED,
    ),
    testsEnded: participantsWithEvent(events, EVENT_TEST_ENDED),
  };
}

/**
 * Kennzahlen je Testperson. Die Reihenfolge folgt der Zeit des ersten
 * Ereignisses – so steht oben, wer zuerst getestet hat. Testpersonen ohne
 * Ereignisse hängen hinten an (sie haben die App nicht benutzt, gehören aber
 * in die Auswertung).
 */
export function statsPerParticipant(
  participants: readonly ParticipantRow[],
  events: readonly EventRow[],
): ParticipantStats[] {
  const byUser = new Map<string, EventRow[]>();
  for (const event of events) {
    const list = byUser.get(event.user_id);
    if (list === undefined) {
      byUser.set(event.user_id, [event]);
    } else {
      list.push(event);
    }
  }

  const stats = participants.map((participant): ParticipantStats => {
    const own = byUser.get(participant.user_id) ?? [];

    // In einem Durchgang statt über `Math.min(...times)`: Der Spread legt
    // jedes Ereignis als eigenes Argument auf den Aufrufstapel, und ein
    // Testtag bringt es auf mehrere tausend – ab einer gewissen Menge wirft
    // das im Browser einen RangeError statt einer Auswertung.
    let min: number | null = null;
    let max: number | null = null;
    for (const event of own) {
      const time = new Date(event.occurred_at).getTime();
      if (Number.isNaN(time)) continue;
      if (min === null || time < min) min = time;
      if (max === null || time > max) max = time;
    }

    return {
      participant,
      sessions: new Set(own.map((event) => event.session_id)).size,
      events: own.length,
      firstActivity: min === null ? null : new Date(min),
      lastActivity: max === null ? null : new Date(max),
      durationMs: min === null || max === null ? null : max - min,
      completedOnboarding: own.some(
        (event) => event.event_name === EVENT_ONBOARDING_COMPLETED,
      ),
      endedTest: own.some((event) => event.event_name === EVENT_TEST_ENDED),
    };
  });

  return stats.sort((a, b) => {
    if (a.firstActivity === null && b.firstActivity === null) {
      return a.participant.display_name.localeCompare(b.participant.display_name);
    }
    if (a.firstActivity === null) return 1;
    if (b.firstActivity === null) return -1;
    return a.firstActivity.getTime() - b.firstActivity.getTime();
  });
}

/**
 * Der Weg durch den Testlauf als Trichter: wie viele Testpersonen haben
 * welchen Schritt erreicht? Zeigt, wo Testpersonen hängen bleiben.
 */
export interface FunnelStep {
  key: string;
  reached: number;
}

export function funnel(
  participants: readonly ParticipantRow[],
  events: readonly EventRow[],
): FunnelStep[] {
  const steps = [
    "test_started",
    "consent_given",
    EVENT_ONBOARDING_COMPLETED,
    EVENT_TEST_ENDED,
  ];
  return [
    { key: "participants", reached: participants.length },
    ...steps.map((key) => ({
      key,
      reached: participantsWithEvent(events, key),
    })),
  ];
}