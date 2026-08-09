// TestAnalyticsService.swift
// Omina – Interaktions-Tracking für den Feldtest.
//
// Zeichnet auf, was Testpersonen anklicken und welche Screens sie öffnen,
// und schreibt die Events in die Supabase-Tabelle `test_events`
// (siehe supabase/migrations/field_test_tables.sql). Events werden lokal gepuffert
// und gebündelt hochgeladen; bei fehlendem Netz bleiben sie in den
// UserDefaults liegen und werden beim nächsten Event / App-Start nachgereicht.
//
// Getrackt wird NUR, wenn eine Feldtest-Session aktiv ist – reguläre
// Accounts erzeugen keine Events.

import Foundation
import Combine
import SwiftUI
import Supabase

/// Eine Zeile in `test_events`.
struct TestEvent: Codable {
    let userId: UUID
    let testProfileKey: String
    let sessionId: UUID
    let eventName: String
    let screen: String?
    let properties: [String: String]?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case testProfileKey = "test_profile_key"
        case sessionId = "session_id"
        case eventName = "event_name"
        case screen
        case properties
        case occurredAt = "occurred_at"
    }
}

@MainActor
final class TestAnalyticsService: ObservableObject {
    static let shared = TestAnalyticsService()

    private let client = SupabaseService.shared.client
    private var pending: [TestEvent] = []
    private var flushTask: Task<Void, Never>?
    /// Verhindert, dass zwei parallele flush()-Aufrufe denselben Batch
    /// doppelt hochladen (z. B. Timer-Flush + flushNow beim Test-Ende).
    private var isFlushing = false

    private static let pendingKey = "omina.fieldTest.pendingEvents"
    /// Kurze Sammelphase, damit schnell aufeinanderfolgende Klicks in einem
    /// Request landen statt einzeln.
    private static let flushDelayNs: UInt64 = 2_000_000_000

    private init() {
        pending = Self.loadPersisted()
        if !pending.isEmpty {
            scheduleFlush()
        }
    }

    /// Zeichnet ein Event auf. No-op, wenn keine Feldtest-Session aktiv ist.
    func track(_ eventName: String, screen: String? = nil, properties: [String: String]? = nil) {
        guard AppConfig.fieldTestModeEnabled,
              let session = FieldTestService.shared.activeSession,
              let userId = AuthService.shared.currentUser?.id else {
            return
        }

        let event = TestEvent(
            userId: userId,
            testProfileKey: session.profileKey,
            sessionId: session.sessionId,
            eventName: eventName,
            screen: screen,
            properties: properties,
            occurredAt: Date()
        )
        pending.append(event)
        persistPending()
        scheduleFlush()
    }

    /// Nonisolated Helfer, damit auch nicht-MainActor-Code (Services,
    /// ViewModels) mit einer Zeile tracken kann.
    nonisolated static func log(_ eventName: String, screen: String? = nil, properties: [String: String]? = nil) {
        Task { @MainActor in
            shared.track(eventName, screen: screen, properties: properties)
        }
    }

    /// Lädt alle gepufferten Events sofort hoch (z. B. beim Beenden eines
    /// Testlaufs, bevor der anonyme User abgemeldet wird).
    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        // Läuft gerade ein Upload, kurz warten, damit auch danach getrackte
        // Events (z. B. "test_ended") noch mitkommen.
        while isFlushing {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await flush()
    }

    // MARK: - Upload

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.flushDelayNs)
            guard !Task.isCancelled else { return }
            await self?.flush()
            self?.flushTask = nil
        }
    }

    private func flush() async {
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        let batch = pending
        do {
            try await client
                .from("test_events")
                .insert(batch)
                .execute()
            // Nur die hochgeladenen Events entfernen; während des Requests
            // können neue dazugekommen sein.
            pending.removeFirst(min(batch.count, pending.count))
            persistPending()
        } catch {
            // Offline oder Serverfehler: Events bleiben im Puffer und werden
            // beim nächsten track()/App-Start erneut versucht.
        }
    }

    // MARK: - Persistenz des Puffers

    private func persistPending() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    private static func loadPersisted() -> [TestEvent] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TestEvent].self, from: data)) ?? []
    }
}

// MARK: - View-Helfer

extension View {
    /// Trackt einen Screen-Aufruf ("screen_view"), sobald die View erscheint.
    func trackScreen(_ name: String, properties: [String: String]? = nil) -> some View {
        onAppear {
            TestAnalyticsService.shared.track("screen_view", screen: name, properties: properties)
        }
    }
}