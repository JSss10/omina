// BarrierFeedback.swift
// Omina
//
// User-Rückmeldung zu einer Barriere – wird vom FeedbackService in die
// Supabase-Tabelle `user_feedback` geschrieben (siehe supabase/schema.sql).
// RLS verlangt user_id == auth.uid(), entsprechend kommt user_id stets aus
// AuthService.shared.currentUser.id.

import Foundation

enum FeedbackType: String, Codable, CaseIterable {
    case valueWrong = "value_wrong"
    case noLongerExists = "no_longer_exists"
    case moved
    case other

    var displayName: String {
        switch self {
        case .valueWrong:     return "Wert stimmt nicht"
        case .noLongerExists: return "Existiert nicht mehr"
        case .moved:          return "An anderer Stelle"
        case .other:          return "Anderes"
        }
    }

    /// Ob für diesen Typ ein „korrekter Wert"-Feld sinnvoll ist.
    var supportsCorrectValue: Bool {
        switch self {
        case .valueWrong: return true
        case .noLongerExists, .moved, .other: return false
        }
    }
}

struct BarrierFeedback: Encodable {
    let barrierId: UUID
    let userId: UUID
    let feedbackType: FeedbackType
    let correctValue: Double?
    let comment: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case barrierId = "barrier_id"
        case userId = "user_id"
        case feedbackType = "feedback_type"
        case correctValue = "correct_value"
        case comment
        case photoUrl = "photo_url"
    }
}