// FeedbackService.swift
// Omina
//
// Schreibt BarrierFeedback in die Supabase-Tabelle `user_feedback`.
// Status defaultet serverseitig auf 'pending' (siehe Database/schema.sql).
//
// Foto-Upload: best effort in den Storage-Bucket
// `feedback-photos`. Existiert der Bucket (noch) nicht oder schlägt der
// Upload fehl, wird das Feedback ohne Foto gespeichert – das Absenden
// scheitert daran nie.

import Foundation
import Supabase

enum FeedbackServiceError: Error {
    case notAuthenticated
}

final class FeedbackService: @unchecked Sendable {
    static let shared = FeedbackService()

    private let client = SupabaseService.shared.client
    private let photoBucket = "feedback-photos"

    func submit(
        barrierId: UUID,
        type: FeedbackType,
        correctValue: Double?,
        comment: String?,
        photoData: Data? = nil
    ) async throws {
        guard let userId = AuthService.shared.currentUser?.id else {
            throw FeedbackServiceError.notAuthenticated
        }

        let trimmedComment = comment?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var photoUrl: String?
        if let photoData {
            photoUrl = await uploadPhoto(photoData, userId: userId)
        }

        let feedback = BarrierFeedback(
            barrierId: barrierId,
            userId: userId,
            feedbackType: type,
            correctValue: type.supportsCorrectValue ? correctValue : nil,
            comment: trimmedComment?.isEmpty == false ? trimmedComment : nil,
            photoUrl: photoUrl
        )

        try await client
            .from("user_feedback")
            .insert(feedback)
            .execute()

        TestAnalyticsService.log(
            "feedback_submitted",
            screen: "feedback_form",
            properties: [
                "barrier_id": barrierId.uuidString,
                "type": type.rawValue,
                "has_photo": photoUrl != nil ? "true" : "false"
            ]
        )
    }

    private func uploadPhoto(_ data: Data, userId: UUID) async -> String? {
        let path = "\(userId.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await client.storage
                .from(photoBucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            return nil
        }
    }
}