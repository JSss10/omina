// ProfileEditView.swift
// ARMikronav
//
// Edit-Formular für ein bestehendes UserProfile. Spiegelt die Felder aus dem
// Onboarding 1.1–1.5 in einem einzelnen Form-Sheet wider, mit lokalem Draft,
// damit Änderungen verworfen werden können. Das Profilfoto (AvatarStore)
// wird direkt gespeichert – Foto aufnehmen (Kamera) oder aus der Galerie
// wählen (PhotosPicker, braucht keine Foto-Berechtigung).

import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: UserProfile

    @State private var draft: UserProfile

    @StateObject private var avatarStore = AvatarStore.shared
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingGalleryPicker = false
    @State private var galleryItem: PhotosPickerItem?

    init(profile: Binding<UserProfile>) {
        self._profile = profile
        self._draft = State(initialValue: profile.wrappedValue)
    }

    var body: some View {
        Form {
            photoSection
            mobilitySection
            wheelchairSection
            measurementsSection
            abilitiesSection
            surfaceSection
            companionSection
        }
        .navigationTitle("Profil bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    draft.updatedAt = Date()
                    profile = draft
                    dismiss()
                }
                .bold()
            }
        }
        // Apple-Muster: ein Tipp auf das Foto öffnet den Aktionsdialog
        // (Action Sheet) mit «Foto aufnehmen / auswählen / entfernen».
        .confirmationDialog(
            "Profilfoto",
            isPresented: $showingPhotoOptions,
            titleVisibility: .visible
        ) {
            Button("Foto aufnehmen") { showingCamera = true }
            Button("Foto auswählen") { showingGalleryPicker = true }
            if avatarStore.image != nil {
                Button("Foto entfernen", role: .destructive) {
                    avatarStore.delete()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showingGalleryPicker,
            selection: $galleryItem,
            matching: .images
        )
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                avatarStore.save(image)
            }
            .ignoresSafeArea()
        }
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

    // MARK: - Profilfoto

    private var photoSection: some View {
        Section {
            // Zentriertes, antippbares Foto nach Apple-Muster (wie Kontakte /
            // Apple-ID): der Tipp öffnet den Aktionsdialog, ein kleines
            // Kamera-Badge signalisiert die Bearbeitbarkeit.
            Button {
                showingPhotoOptions = true
            } label: {
                VStack(spacing: AppMetrics.Space.s) {
                    avatarPreview
                    Text(avatarStore.image == nil ? "Foto hinzufügen" : "Foto bearbeiten")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppMetrics.Space.s)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Profilfoto")
        } footer: {
            Text("Das Foto wird sofort übernommen und erscheint auf dem Homescreen.")
        }
    }

    private var avatarPreview: some View {
        ZStack {
            if let photo = avatarStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(AppColor.accentPrimary)
                Image(systemName: "person.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppColor.onAccent)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) { editBadge }
        .accessibilityHidden(true)
    }

    /// Kleines Kamera-Badge unten rechts – Apples Standard-Hinweis, dass das
    /// Foto antippbar/änderbar ist.
    private var editBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColor.onAccent)
            .frame(width: 30, height: 30)
            .background(AppColor.accentPrimary, in: Circle())
            .overlay(
                Circle().strokeBorder(AppColor.backgroundPrimary, lineWidth: 2)
            )
    }

    // MARK: - Sections

    private var mobilitySection: some View {
        Section("Mobilitätskategorie") {
            Picker("Kategorie", selection: $draft.mobilityCategory) {
                ForEach(MobilityCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
        }
    }

    private var wheelchairSection: some View {
        Section("Rollstuhltyp") {
            Picker("Typ", selection: $draft.wheelchairType) {
                ForEach(WheelchairType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
        }
    }

    private var measurementsSection: some View {
        Section {
            Stepper("Breite: \(draft.widthCm) cm",
                    value: $draft.widthCm, in: 50...100, step: 1)
            Stepper("Gesamthöhe (sitzend): \(draft.heightCm) cm",
                    value: $draft.heightCm, in: 100...180, step: 1)
            Stepper("Sitzhöhe: \(draft.seatHeightCm) cm",
                    value: $draft.seatHeightCm, in: 35...70, step: 1)
            Stepper("Länge: \(draft.lengthCm) cm",
                    value: $draft.lengthCm, in: 80...160, step: 1)
            Stepper("Gewicht: \(draft.weightKg) kg",
                    value: $draft.weightKg, in: 30...200, step: 1)
        } header: {
            Text("Maße")
        } footer: {
            Text("Die Sitzhöhe (Sitzfläche inkl. Kissen ab Boden) bestimmt zusammen mit der Gesamthöhe, auf welcher Höhe der AR-Pfad auf dem Boden angezeigt wird.")
        }
    }

    private var abilitiesSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text(String(format: "Tempo: %.1f km/h", draft.travelSpeedKmh))
                Slider(
                    value: $draft.travelSpeedKmh,
                    in: UserProfile.minTravelSpeedKmh...UserProfile.maxTravelSpeedKmh,
                    step: 0.5
                )
            }
            VStack(alignment: .leading) {
                Text("Max. Steigung: \(Int(draft.maxIncline)) %")
                Slider(value: $draft.maxIncline, in: 0...15, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Max. Bordsteinhöhe: \(Int(draft.maxCurbHeight)) cm")
                Slider(value: $draft.maxCurbHeight, in: 0...15, step: 1)
            }
            Stepper("Manövrier-Spielraum: +\(draft.maneuverBufferCm) cm",
                    value: $draft.maneuverBufferCm, in: 0...25, step: 1)
        } header: {
            Text("Was du bewältigst")
        } footer: {
            Text("Werte beziehen sich aufs Fahren ohne Begleitung. Mit Begleitung werden sie automatisch leicht erhöht. Das Tempo bestimmt Fahrzeit und Ankunftszeit einer Route.")
        }
    }

    private var surfaceSection: some View {
        Section("Oberflächentoleranz") {
            Picker("Toleranz", selection: $draft.surfaceTolerance) {
                ForEach(SurfaceTolerance.allCases, id: \.self) { tolerance in
                    Text(tolerance.displayName).tag(tolerance)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var companionSection: some View {
        Section {
            Picker("Standard", selection: $draft.companionStatus) {
                ForEach(CompanionStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            if draft.companionStatus != .alwaysAlone {
                VStack(alignment: .leading) {
                    Text("Mit Begleitung: +\(Int(draft.companionInclineBonus)) % Steigung")
                    Slider(value: $draft.companionInclineBonus, in: 0...6, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Mit Begleitung: +\(Int(draft.companionCurbBonus)) cm Bordstein")
                    Slider(value: $draft.companionCurbBonus, in: 0...8, step: 1)
                }
            }
            Toggle("Ich besitze einen Eurokey", isOn: $draft.hasEurokey)
        } header: {
            Text("Begleitung & Ausstattung")
        } footer: {
            if draft.companionStatus != .alwaysAlone {
                Text("Die Begleit-Werte werden zu deinen Limits addiert, wenn du mit Begleitung unterwegs bist. Mit Eurokey werden abgeschlossene Behinderten-WCs als zugänglich bewertet.")
            } else {
                Text("Mit Eurokey werden abgeschlossene Behinderten-WCs für dich als zugänglich bewertet.")
            }
        }
    }
}