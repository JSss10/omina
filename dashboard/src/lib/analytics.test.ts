// analytics.test.ts
// Tests der Auswertungslogik.
//
// Geprüft wird das, was in die Arbeit einfliesst: Zählungen, Dauern und die
// Zuordnung von Ereignissen zu Testpersonen. Fehler hier wären in den
// Ergebnissen nicht als Fehler erkennbar – sie sähen aus wie Messwerte.

import { describe, expect, test } from "vitest";
import {
  countBy,
  countEventNames,
  countScreenViews,
  funnel,
  sessionDurations,
  statsPerParticipant,
  summarise,
} from "./analytics.ts";
import type { EventRow, ParticipantRow } from "./types.ts";

const USER_A = "11111111-1111-1111-1111-111111111111";
const USER_B = "22222222-2222-2222-2222-222222222222";

function participant(
  userId: string,
  overrides: Partial<ParticipantRow> = {},
): ParticipantRow {
  return {
    id: `p-${userId}`,
    user_id: userId,
    test_profile_key: "tp01",
    display_name: "Testperson",
    test_day: "2026-07-21",
    profile: null,
    device_model: "iPhone",
    app_version: "1.0",
    created_at: "2026-07-21T08:00:00Z",
    updated_at: "2026-07-21T08:00:00Z",
    ...overrides,
  };
}

function event(
  userId: string,
  eventName: string,
  occurredAt: string,
  overrides: Partial<EventRow> = {},
): EventRow {
  return {
    id: `e-${userId}-${occurredAt}-${eventName}`,
    user_id: userId,
    test_profile_key: "tp01",
    session_id: `s-${userId}`,
    event_name: eventName,
    screen: null,
    properties: null,
    occurred_at: occurredAt,
    created_at: occurredAt,
    ...overrides,
  };
}

describe("countBy", () => {
  test("zählt absteigend und lässt leere Schlüssel weg", () => {
    const events = [
      event(USER_A, "screen_view", "2026-07-21T08:00:00Z", { screen: "search" }),
      event(USER_A, "screen_view", "2026-07-21T08:01:00Z", { screen: "search" }),
      event(USER_A, "screen_view", "2026-07-21T08:02:00Z", { screen: "filter" }),
      event(USER_A, "screen_view", "2026-07-21T08:03:00Z", { screen: null }),
    ];

    expect(countBy(events, (e) => e.screen)).toEqual([
      { key: "search", count: 2 },
      { key: "filter", count: 1 },
    ]);
  });

  test("sortiert gleich häufige Einträge alphabetisch, damit die Reihenfolge stabil bleibt", () => {
    const events = [
      event(USER_A, "screen_view", "2026-07-21T08:00:00Z", { screen: "zuletzt" }),
      event(USER_A, "screen_view", "2026-07-21T08:01:00Z", { screen: "anfang" }),
    ];

    expect(countBy(events, (e) => e.screen).map((entry) => entry.key)).toEqual([
      "anfang",
      "zuletzt",
    ]);
  });
});

describe("countScreenViews", () => {
  test("zählt nur screen_view, nicht andere Ereignisse mit Screen-Angabe", () => {
    const events = [
      event(USER_A, "screen_view", "2026-07-21T08:00:00Z", { screen: "consent" }),
      // consent_given trägt ebenfalls einen Screen, ist aber kein Aufruf.
      event(USER_A, "consent_given", "2026-07-21T08:00:30Z", {
        screen: "consent",
      }),
    ];

    expect(countScreenViews(events)).toEqual([{ key: "consent", count: 1 }]);
  });
});

describe("countEventNames", () => {
  test("zählt über alle Ereignisnamen", () => {
    const events = [
      event(USER_A, "screen_view", "2026-07-21T08:00:00Z"),
      event(USER_A, "screen_view", "2026-07-21T08:01:00Z"),
      event(USER_B, "test_ended", "2026-07-21T08:02:00Z"),
    ];

    expect(countEventNames(events)).toEqual([
      { key: "screen_view", count: 2 },
      { key: "test_ended", count: 1 },
    ]);
  });
});

describe("sessionDurations", () => {
  test("misst vom ersten bis zum letzten Ereignis eines Testlaufs", () => {
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z", { session_id: "s1" }),
      event(USER_A, "screen_view", "2026-07-21T08:05:00Z", { session_id: "s1" }),
      event(USER_A, "test_ended", "2026-07-21T08:12:30Z", { session_id: "s1" }),
    ];

    expect(sessionDurations(events).get("s1")).toBe(12.5 * 60 * 1000);
  });

  test("ein einzelnes Ereignis ergibt Dauer 0 und zählt als Testlauf", () => {
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z", { session_id: "s1" }),
    ];

    const durations = sessionDurations(events);
    expect(durations.size).toBe(1);
    expect(durations.get("s1")).toBe(0);
  });

  test("hält Testläufe auseinander", () => {
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z", { session_id: "s1" }),
      event(USER_A, "test_ended", "2026-07-21T08:10:00Z", { session_id: "s1" }),
      event(USER_B, "test_started", "2026-07-21T09:00:00Z", { session_id: "s2" }),
      event(USER_B, "test_ended", "2026-07-21T09:20:00Z", { session_id: "s2" }),
    ];

    const durations = sessionDurations(events);
    expect(durations.get("s1")).toBe(10 * 60 * 1000);
    expect(durations.get("s2")).toBe(20 * 60 * 1000);
  });
});

describe("summarise", () => {
  test("zählt Testpersonen, Testläufe und Ereignisse", () => {
    const participants = [participant(USER_A), participant(USER_B)];
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z", { session_id: "s1" }),
      event(USER_A, "onboarding_completed", "2026-07-21T08:05:00Z", {
        session_id: "s1",
      }),
      event(USER_A, "test_ended", "2026-07-21T08:20:00Z", { session_id: "s1" }),
      event(USER_B, "test_started", "2026-07-21T09:00:00Z", { session_id: "s2" }),
    ];

    const summary = summarise(participants, events);

    expect(summary.participants).toBe(2);
    expect(summary.sessions).toBe(2);
    expect(summary.events).toBe(4);
    expect(summary.onboardingCompleted).toBe(1);
    expect(summary.testsEnded).toBe(1);
    expect(summary.averageEventsPerParticipant).toBe(2);
    // (20 min + 0 min) / 2
    expect(summary.averageSessionMs).toBe(10 * 60 * 1000);
  });

  test("zählt eine Testperson auch bei mehreren gleichen Ereignissen nur einmal", () => {
    const participants = [participant(USER_A)];
    const events = [
      event(USER_A, "onboarding_completed", "2026-07-21T08:05:00Z"),
      event(USER_A, "onboarding_completed", "2026-07-21T08:06:00Z"),
    ];

    expect(summarise(participants, events).onboardingCompleted).toBe(1);
  });

  test("ohne Daten bleiben die Mittelwerte leer statt 0", () => {
    const summary = summarise([], []);
    expect(summary.averageSessionMs).toBeNull();
    expect(summary.averageEventsPerParticipant).toBeNull();
  });
});

describe("statsPerParticipant", () => {
  test("ordnet Ereignisse der richtigen Testperson zu", () => {
    const participants = [
      participant(USER_A, { display_name: "Anna" }),
      participant(USER_B, { display_name: "Bea" }),
    ];
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z", { session_id: "s1" }),
      event(USER_A, "test_ended", "2026-07-21T08:30:00Z", { session_id: "s1" }),
      event(USER_B, "test_started", "2026-07-21T09:00:00Z", { session_id: "s2" }),
    ];

    const [anna, bea] = statsPerParticipant(participants, events);

    expect(anna?.participant.display_name).toBe("Anna");
    expect(anna?.events).toBe(2);
    expect(anna?.durationMs).toBe(30 * 60 * 1000);
    expect(anna?.endedTest).toBe(true);

    expect(bea?.events).toBe(1);
    expect(bea?.endedTest).toBe(false);
  });

  test("Testpersonen ohne Ereignisse bleiben in der Auswertung, aber hinten", () => {
    const participants = [
      participant(USER_A, { display_name: "Ohne Aktivität" }),
      participant(USER_B, { display_name: "Mit Aktivität" }),
    ];
    const events = [event(USER_B, "test_started", "2026-07-21T09:00:00Z")];

    const stats = statsPerParticipant(participants, events);

    expect(stats).toHaveLength(2);
    expect(stats[0]?.participant.display_name).toBe("Mit Aktivität");
    expect(stats[1]?.participant.display_name).toBe("Ohne Aktivität");
    expect(stats[1]?.durationMs).toBeNull();
    expect(stats[1]?.firstActivity).toBeNull();
  });

  test("sortiert nach dem ersten Ereignis, nicht nach der Reihenfolge der Eingabe", () => {
    const participants = [
      participant(USER_A, { display_name: "Später" }),
      participant(USER_B, { display_name: "Früher" }),
    ];
    const events = [
      event(USER_A, "test_started", "2026-07-21T10:00:00Z"),
      event(USER_B, "test_started", "2026-07-21T08:00:00Z"),
    ];

    expect(
      statsPerParticipant(participants, events).map(
        (entry) => entry.participant.display_name,
      ),
    ).toEqual(["Früher", "Später"]);
  });
});

describe("funnel", () => {
  test("zeigt, wie viele Testpersonen welchen Schritt erreicht haben", () => {
    const participants = [participant(USER_A), participant(USER_B)];
    const events = [
      event(USER_A, "test_started", "2026-07-21T08:00:00Z"),
      event(USER_B, "test_started", "2026-07-21T09:00:00Z"),
      event(USER_A, "consent_given", "2026-07-21T08:01:00Z"),
      event(USER_B, "consent_given", "2026-07-21T09:01:00Z"),
      event(USER_A, "onboarding_completed", "2026-07-21T08:05:00Z"),
      event(USER_A, "test_ended", "2026-07-21T08:30:00Z"),
    ];

    expect(funnel(participants, events)).toEqual([
      { key: "participants", reached: 2 },
      { key: "test_started", reached: 2 },
      { key: "consent_given", reached: 2 },
      { key: "onboarding_completed", reached: 1 },
      { key: "test_ended", reached: 1 },
    ]);
  });
});