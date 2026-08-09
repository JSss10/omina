// AvatarStore.swift
// Omina
//
// Profilfoto des Users. Offline-first wie das Profil (B1): das Bild liegt
// primär als JPEG im Documents-Verzeichnis, beim Speichern läuft zusätzlich
// ein Best-Effort-Upload in den Supabase-Storage-Bucket "avatars"
// (Pfad <user_id>/avatar.jpg, RLS: user-owned – siehe
// supabase/migrations/avatars_bucket.sql). Auf einem frischen Gerät wird das Foto
// einmalig aus dem Bucket zurückgeholt und lokal gecached.

import UIKit
import Combine
import Supabase

@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published private(set) var image: UIImage?

    private let bucket = "avatars"
    /// Kantenlänge, auf die das Foto vor dem Speichern verkleinert wird.
    private let maxDimension: CGFloat = 512
    private var hasFetchedRemote = false

    private init() {
        image = Self.readFromDisk()
    }

    /// Lädt das Foto vom Server nach, falls lokal keines liegt (z. B. nach
    /// App-Reinstall oder auf neuem Gerät). Einmalig pro App-Start.
    func loadIfNeeded() {
        guard image == nil, !hasFetchedRemote else { return }
        hasFetchedRemote = true
        Task {
            guard let path = Self.remotePath() else { return }
            guard let data = try? await SupabaseService.shared.client.storage
                .from(bucket)
                .download(path: path) else { return }
            if let downloaded = UIImage(data: data) {
                image = downloaded
                Self.writeToDisk(data)
            }
        }
    }

    /// Verkleinert das Foto, speichert es lokal und lädt es best-effort in
    /// den Storage-Bucket hoch.
    func save(_ newImage: UIImage) {
        let resized = Self.resize(newImage, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return }

        image = resized
        Self.writeToDisk(data)

        Task {
            guard let path = Self.remotePath() else { return }
            _ = try? await SupabaseService.shared.client.storage
                .from(bucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
                )
        }
    }

    /// Entfernt das Foto lokal und best-effort auch aus dem Bucket.
    func delete() {
        image = nil
        try? FileManager.default.removeItem(at: Self.fileURL)

        Task {
            guard let path = Self.remotePath() else { return }
            _ = try? await SupabaseService.shared.client.storage
                .from(bucket)
                .remove(paths: [path])
        }
    }

    // MARK: - Lokale Datei

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatar.jpg")
    }

    private static func readFromDisk() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private static func writeToDisk(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Remote

    private static func remotePath() -> String? {
        guard let userId = AuthService.shared.currentUser?.id else { return nil }
        return "\(userId.uuidString.lowercased())/avatar.jpg"
    }

    // MARK: - Bildverarbeitung

    /// Skaliert das Bild proportional auf maximal `maxDimension` pt Kante.
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1)
        guard scale < 1 else { return image }

        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}