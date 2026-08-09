// ProfileSetupScreen.swift
// Omina – Onboarding Schritt 1/8: Name und Profilbild.
// Aufbau nach Entwurf: getönter Kreis mit Personen-Symbol als Profilbild,
// darunter Vorname und Nachname als Felder ohne eigene Label-Zeile.
//
// Name bei E-Mail-Registrierung vorbelegt aus user_metadata; Pflichtfeld bei
// Apple/Google Sign-in. Das Profilbild ist optional: Ein Tap aufs Foto öffnet
// Apples nativen Auswahldialog (Foto aufnehmen via Kamera oder Bild hochladen
// aus der Galerie via PhotosPicker). Die X-Schaltfläche am Bild entfernt es.
// Gespeichert wird direkt über den AvatarStore (lokal + Storage-Sync).

import SwiftUI
import PhotosUI

struct Screen10_ProfileSetup: View {
    @Binding var draft: DraftProfile

    @StateObject private var avatarStore = AvatarStore.shared
    @State private var showingCamera = false
    @State private var galleryItem: PhotosPickerItem?
    /// Steuert den nativen Auswahldialog (Foto aufnehmen / Bild hochladen).
    @State private var showingPhotoOptions = false
    @State private var showingGalleryPicker = false

    /// Durchmesser des Profilbilds bzw. seines Platzhalter-Kreises (Entwurf).
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 140

    var body: some View {
        VStack(spacing: AppMetrics.Space.xxl) {
            avatarPreview
                .padding(.top, AppMetrics.Space.s)

            VStack(spacing: AppMetrics.Space.m) {
                AppTextField(
                    placeholder: "Vorname",
                    text: $draft.firstName,
                    textContentType: .givenName,
                    autocapitalization: .words
                )

                AppTextField(
                    placeholder: "Nachname",
                    text: $draft.lastName,
                    textContentType: .familyName,
                    autocapitalization: .words
                )
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                avatarStore.save(image)
            }
            .ignoresSafeArea()
        }
        // Ein Tap aufs Foto öffnet Apples nativen Auswahldialog.
        .confirmationDialog("Profilbild", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
            Button("Foto aufnehmen") { showingCamera = true }
            Button("Bild hochladen") { showingGalleryPicker = true }
            Button("Abbrechen", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingGalleryPicker, selection: $galleryItem, matching: .images)
        .onChange(of: galleryItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarStore.save(image)
                }
                galleryItem = nil
            }
        }
    }

    // MARK: - Profilbild

    private var avatarPreview: some View {
        // Tap aufs Foto öffnet den nativen Auswahldialog; die X-Schaltfläche
        // oben rechts (nur bei gesetztem Bild) entfernt das Profilbild.
        Button {
            showingPhotoOptions = true
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let photo = avatarStore.image {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(AppColor.surfaceTinted)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: avatarSize / 3, weight: .regular))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())

                if avatarStore.image != nil {
                    Button {
                        avatarStore.delete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppColor.onAccent, AppColor.accentPrimary)
                    }
                    .accessibilityLabel("Foto entfernen")
                    .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatarStore.image == nil ? "Profilbild hinzufügen" : "Profilbild ändern")
        .accessibilityHint("Optional. Öffnet die Auswahl zwischen Kamera und Fotomediathek.")
    }
}