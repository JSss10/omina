// types.ts
// Zeilentypen der Feldtest-Tabellen (supabase/migrations/field_test_tables.sql) und
// das Onboarding-Profil, das die App als JSON in `test_participants.profile`
// ablegt.

/** Eine Zeile aus `test_participants`. */
export interface ParticipantRow {
  id: string;
  user_id: string;
  test_profile_key: string;
  display_name: string;
  test_day: string;
  profile: OnboardingProfile | null;
  device_model: string | null;
  app_version: string | null;
  created_at: string;
  updated_at: string;
}

/** Eine Zeile aus `test_events`. */
export interface EventRow {
  id: string;
  user_id: string;
  test_profile_key: string;
  session_id: string;
  event_name: string;
  screen: string | null;
  properties: Record<string, string> | null;
  occurred_at: string;
  created_at: string;
}

/** Testtag mit Anzahl Testpersonen (RPC `field_test_days`). */
export interface TestDayRow {
  test_day: string;
  participant_count: number;
}

/**
 * Die Onboarding-Antworten, wie `FieldTestService.saveOnboardingProfile()`
 * sie schreibt: Swifts `UserProfile` mit den synthetisierten CodingKeys,
 * also camelCase (im Unterschied zu den snake_case-Spalten der Tabelle).
 *
 * Alle Felder sind optional, weil ältere Zeilen aus früheren Testtagen
 * entstanden sein können, bevor ein Feld existierte – die App dekodiert
 * genauso nachsichtig (siehe `UserProfile.init(from:)`).
 */
export interface OnboardingProfile {
  id?: string;
  mobilityCategory?: MobilityCategory;
  wheelchairType?: WheelchairType;
  widthCm?: number;
  heightCm?: number;
  weightKg?: number;
  seatHeightCm?: number;
  lengthCm?: number;
  travelSpeedKmh?: number;
  maxIncline?: number;
  maxCurbHeight?: number;
  surfaceTolerance?: SurfaceTolerance;
  maneuverBufferCm?: number;
  companionStatus?: CompanionStatus;
  companionTodayOverride?: boolean;
  companionInclineBonus?: number;
  companionCurbBonus?: number;
  wetConditionsToday?: boolean;
  lowEnergyToday?: boolean;
  hasEurokey?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export type WheelchairType =
  | "manual"
  | "emotion"
  | "joystick"
  | "electric"
  | "stairClimbing";

export type MobilityCategory =
  | "none"
  | "wheelchair"
  | "visualImpairment"
  | "blind"
  | "hearingImpairment"
  | "deaf"
  | "walkingDisability"
  | "stroller"
  | "rollator"
  | "elderly";

export type SurfaceTolerance = "smoothOnly" | "fineCobble" | "almostAll";

export type CompanionStatus = "alwaysAlone" | "sometimes" | "usually";