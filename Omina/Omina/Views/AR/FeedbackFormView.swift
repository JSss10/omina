// FeedbackFormView.swift
// Omina
//
// Formular für "Stimmt nicht mehr?" – User meldet, wenn eine Barriere
// falsche Werte hat, weg ist, verschoben wurde oder sonst etwas auffällt.
// Wird vom BarrierDetailSheet als Sheet aufgerufen.

import SwiftUI
import PhotosUI

struct FeedbackFormView: View {
    let barrier: Barrier
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .valueWrong
    @State private var correctValueText: String = ""
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var photoData: Data?
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                if feedbackType.supportsCorrectValue {
                    correctValueSection
                }
                commentSection
                photoSection
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("feedback_form", properties: ["barrier_id": barrier.id.uuidString])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { submit() }
                        .bold()
                        .disabled(isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.large)
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            // Action Sheet für die Foto-Quelle
            .confirmationDialog("Foto hinzufügen", isPresented: $showingPhotoOptions, titleVisibility: .hidden) {
                Button("Foto aufnehmen") { showingCamera = true }
                Button("Aus Galerie wählen") { showingLibrary = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    photoData = image.jpegData(compressionQuality: 0.7)
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    photoData = try? await item.loadTransferable(type: Data.self)
                    libraryItem = nil
                }
            }
        }
    }

    // MARK: - Foto

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let photoData, let image = UIImage(data: photoData) {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Foto angehängt")
                        .font(.subheadline)
                    Spacer()
                    Button(role: .destructive) {
                        self.photoData = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Foto entfernen")
                }
            } else {
                Button {
                    showingPhotoOptions = true
                } label: {
                    Label("Foto hinzufügen", systemImage: "camera")
                }
            }
        } footer: {
            Text("Dein Feedback hilft anderen Nutzer:innen. Vielen Dank!")
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section {
            Picker("Was stimmt nicht?", selection: $feedbackType) {
                ForEach(FeedbackType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Was stimmt nicht?")
        } footer: {
            Text("Barriere: \(barrier.type.localizedLabel)")
        }
    }

    private var correctValueSection: some View {
        Section {
            HStack {
                TextField("Korrekter Wert", text: $correctValueText)
                    .keyboardType(.decimalPad)
                Text(unitHint)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Falls du den richtigen Wert kennst (z. B. die tatsächliche Stufenanzahl oder Höhe). Optional.")
        }
    }

    private var commentSection: some View {
        Section("Kommentar") {
            TextField("Optional", text: $comment, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var unitHint: String {
        switch barrier.type {
        case .steps: return "Stufen"
        case .curb, .curbMissing, .narrow: return "cm"
        case .incline: return "%"
        case .surface, .temporary: return ""
        }
    }

    // MARK: - Submission

    private func submit() {
        let value = Double(correctValueText.replacingOccurrences(of: ",", with: "."))
        let commentToSend = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await FeedbackService.shared.submit(
                    barrierId: barrier.id,
                    type: feedbackType,
                    correctValue: value,
                    comment: commentToSend.isEmpty ? nil : commentToSend,
                    photoData: photoData
                )
                isSubmitting = false
                onSubmitted()
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}