// format.ts
// Beschriftungen und Formatierung. Die Wörter sind dieselben, die die App den
// Testpersonen zeigt – damit die Auswertung nicht mit Rohschlüsseln aus der
// Datenbank arbeitet, sondern mit lesbarem Deutsch.

import type {
  CompanionStatus,
  MobilityCategory,
  SurfaceTolerance,
  WheelchairType,
} from "./types.ts";

const LOCALE = "de-CH";

const dateTimeFormat = new Intl.DateTimeFormat(LOCALE, {
  dateStyle: "short",
  timeStyle: "medium",
});

const timeFormat = new Intl.DateTimeFormat(LOCALE, {
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

const dayFormat = new Intl.DateTimeFormat(LOCALE, {
  weekday: "long",
  day: "2-digit",
  month: "long",
  year: "numeric",
});

const numberFormat = new Intl.NumberFormat(LOCALE);

const decimalFormat = new Intl.NumberFormat(LOCALE, {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

export function formatNumber(value: number): string {
  return numberFormat.format(value);
}

export function formatDecimal(value: number): string {
  return decimalFormat.format(value);
}

export function formatDateTime(iso: string): string {
  return dateTimeFormat.format(new Date(iso));
}

export function formatTime(iso: string): string {
  return timeFormat.format(new Date(iso));
}

/** «Dienstag, 21. Juli 2026» – aus einem reinen Datum (yyyy-MM-dd). */
export function formatTestDay(day: string): string {
  // Ohne Zeitanteil interpretiert der Browser den String als UTC-Mitternacht;
  // in einer Zone östlich von UTC wäre das der Vortag. Deshalb explizit als
  // lokales Datum bauen.
  const parts = day.split("-").map(Number);
  const [year, month, date] = parts;
  if (year === undefined || month === undefined || date === undefined) {
    return day;
  }
  return dayFormat.format(new Date(year, month - 1, date));
}

/** Dauer in Millisekunden als «12 min 34 s» bzw. «1 h 05 min». */
export function formatDuration(ms: number | null): string {
  if (ms === null || !Number.isFinite(ms) || ms < 0) return "–";
  const totalSeconds = Math.round(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours} h ${String(minutes).padStart(2, "0")} min`;
  }
  if (minutes > 0) {
    return `${minutes} min ${String(seconds).padStart(2, "0")} s`;
  }
  return `${seconds} s`;
}

// ---------------------------------------------------------------
// Beschriftungen der Enum-Werte aus dem Onboarding
// ---------------------------------------------------------------

const WHEELCHAIR_LABELS: Record<WheelchairType, string> = {
  manual: "Manueller Rollstuhl",
  emotion: "e-motion (Zusatzantrieb)",
  joystick: "Joystick-Antrieb",
  electric: "Elektrorollstuhl",
  stairClimbing: "Treppensteiger (Scewo BRO)",
};

const MOBILITY_LABELS: Record<MobilityCategory, string> = {
  none: "Keine Einschränkung",
  wheelchair: "Rollstuhl",
  visualImpairment: "Sehbehinderung",
  blind: "Blind",
  hearingImpairment: "Hörbehinderung",
  deaf: "Gehörlos",
  walkingDisability: "Gehbehinderung",
  stroller: "Kinderwagen",
  rollator: "Rollator",
  elderly: "Ältere Person",
};

const SURFACE_LABELS: Record<SurfaceTolerance, string> = {
  smoothOnly: "Nur glatte Beläge",
  fineCobble: "Feines Pflaster geht",
  almostAll: "Fast alles geht",
};

const COMPANION_LABELS: Record<CompanionStatus, string> = {
  alwaysAlone: "Immer allein unterwegs",
  sometimes: "Manchmal mit Begleitung",
  usually: "Meistens mit Begleitung",
};

/** Beschriftung aus einer Zuordnung; unbekannte Werte bleiben sichtbar. */
function label<T extends string>(
  map: Record<T, string>,
  value: T | undefined,
): string {
  if (value === undefined) return "–";
  return map[value] ?? value;
}

export const wheelchairLabel = (v: WheelchairType | undefined): string =>
  label(WHEELCHAIR_LABELS, v);
export const mobilityLabel = (v: MobilityCategory | undefined): string =>
  label(MOBILITY_LABELS, v);
export const surfaceLabel = (v: SurfaceTolerance | undefined): string =>
  label(SURFACE_LABELS, v);
export const companionLabel = (v: CompanionStatus | undefined): string =>
  label(COMPANION_LABELS, v);

// ---------------------------------------------------------------
// Beschriftungen der Tracking-Ereignisse
// (Aufrufstellen: TestAnalyticsService.log / .track in der App)
// ---------------------------------------------------------------

const EVENT_LABELS: Record<string, string> = {
  test_started: "Testlauf gestartet",
  consent_given: "Einwilligung erteilt",
  onboarding_next: "Onboarding: weiter",
  onboarding_back: "Onboarding: zurück",
  onboarding_completed: "Onboarding abgeschlossen",
  screen_view: "Screen geöffnet",
  feedback_submitted: "Feedback abgeschickt",
  test_ended: "Testlauf beendet",
};

const SCREEN_LABELS: Record<string, string> = {
  consent: "Einwilligung",
  onboarding: "Onboarding",
  ar_mode: "AR-Modus",
  ar_search: "Suche im AR-Modus",
  barrier_detail: "Barrieren-Detail",
  feedback_form: "Feedback-Formular",
  filter: "Filter",
  map_settings: "Karteneinstellungen",
  poi_detail: "Ort-Detail",
  route_barrier_list: "Barrieren entlang der Route",
  route_steps_list: "Wegbeschreibung",
  search: "Suche",
  settings: "Einstellungen",
};

/** Unbekannte Schlüssel werden lesbar gemacht statt verschluckt. */
function humanise(key: string): string {
  const words = key.replace(/_/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function eventLabel(name: string): string {
  return EVENT_LABELS[name] ?? humanise(name);
}

export function screenLabel(screen: string): string {
  return SCREEN_LABELS[screen] ?? humanise(screen);
}

/** `properties` als kompakte Zeile «poi: Café Schober · dauer: 12». */
export function formatProperties(
  properties: Record<string, string> | null,
): string {
  if (!properties) return "";
  const entries = Object.entries(properties);
  if (entries.length === 0) return "";
  return entries.map(([key, value]) => `${key}: ${value}`).join(" · ");
}