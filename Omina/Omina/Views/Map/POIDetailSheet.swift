// POIDetailSheet.swift
// Omina
//
// POI-Detail als Bottom-Sheet, Aufbau nach Entwurf: zuoberst das Foto über die
// ganze Breite mit Teilen- und Schliessen-Schaltfläche, darunter Name mit
// Distanz, Kategorie und Adresse, die Zugänglichkeit in einer Zeile und die
// drei Aktionen als Kacheln. Danach folgen die Angaben aus dem Open-Data-API
// von Zürich Tourismus: Beschreibung, Stichpunkte, Öffnungszeiten, Kontakt
// und Preisniveau.
//
// Die Zugänglichkeit steht ausschliesslich oben in der Statuszeile unter der
// Adresse – der ausführliche Bewertungsblock am Ende des Sheets ist bewusst
// weggefallen.
//
// Styling gemäss Styleguide v1.0: ausschliesslich Design-Tokens (AppColor,
// AppTypography, AppMetrics) und die gemeinsamen Komponenten.

import SwiftUI
import MapKit
import Supabase

struct POIDetailSheet: View {
    let poi: POI
    /// Profil des Users – bestimmt, welche ginto-Bewertung angezeigt wird
    /// (nur der eigene Rollstuhltyp, nicht alle Profile).
    let profile: UserProfile
    /// Startet die AR-Navigation zu diesem POI. Ohne Callback bleibt die
    /// Kachel deaktiviert (Kontext ohne AR-Zugang).
    var onStartARRoute: ((POI) -> Void)? = nil
    /// Berechnet die Route in-App und zeigt sie auf der Karte. Ohne Callback
    /// öffnet «Route» als Fallback Apple Maps.
    var onShowRoute: ((POI) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var saveState: SaveState = .idle
    @State private var photoIndex = 0

    enum SaveState {
        case idle, saving, saved, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    header
                    actionRow

                    sectionDivider

                    aboutSection
                    highlightsSection
                    openingHoursCard
                    contactSection
                    eurokeyHint
                    infoSourceNote
                }
                .padding(AppMetrics.Space.l)
            }
        }
        .background(AppColor.backgroundPrimary)
        .presentationBackground(AppColor.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AppMetrics.Radius.sheet + AppMetrics.Space.s)
    }

    // MARK: - Foto mit Aktionen

    /// Foto über die ganze Sheet-Breite; darauf liegen Teilen und Schliessen
    /// als weisse Kreise (Entwurf).
    private var hero: some View {
        ZStack(alignment: .top) {
            photoCarousel
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()

            HStack {
                shareButton
                Spacer()
                closeButton
            }
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.top, AppMetrics.Space.xl)
        }
    }

    private var shareButton: some View {
        ShareLink(item: shareText) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppColor.textBrand)
                .frame(width: AppMetrics.Touch.minimum + 4, height: AppMetrics.Touch.minimum + 4)
                .background(AppColor.backgroundPrimary, in: Circle())
        }
        .accessibilityLabel("Ort teilen")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppColor.textBrand)
                .frame(width: AppMetrics.Touch.minimum + 4, height: AppMetrics.Touch.minimum + 4)
                .background(AppColor.backgroundPrimary, in: Circle())
        }
        .accessibilityLabel("Schliessen")
    }

    /// Text zum Teilen: Name, Adresse und – wenn vorhanden – die Detailseite.
    private var shareText: String {
        var parts = [poi.name]
        if let address = poi.address { parts.append(address) }
        if let url = poi.zuerichURL ?? poi.websiteURL { parts.append(url.absoluteString) }
        return parts.joined(separator: "\n")
    }

    /// Foto-Karussell des Ortes. Bei mehreren Bildern paged mit Indikatoren.
    /// Kennt das Zürich-Tourismus-API den Ort nicht, steht hier ein Platzhalter.
    @ViewBuilder
    private var photoCarousel: some View {
        let images = poi.images
        if images.isEmpty {
            photoPlaceholder
        } else if images.count == 1 {
            photo(images[0])
                .accessibilityLabel(photoAccessibilityLabel(images))
        } else {
            TabView(selection: $photoIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    photo(image).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .accessibilityLabel(photoAccessibilityLabel(images))
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            AppColor.surfaceTinted
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kein Foto von \(poi.name) verfügbar")
    }

    private func photo(_ image: POIImage) -> some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let loaded):
                loaded
                    .resizable()
                    .scaledToFill()
            case .failure:
                photoPlaceholder
            default:
                ZStack {
                    AppColor.surfaceTinted
                    ProgressView()
                        .tint(AppColor.accentPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Ein Sammel-Label statt vieler Einzelbilder: VoiceOver liest die Anzahl,
    /// die Bildunterschriften und den Bildnachweis am Stück.
    private func photoAccessibilityLabel(_ images: [POIImage]) -> String {
        var parts = [images.count == 1 ? "Foto von \(poi.name)"
                                       : "\(images.count) Fotos von \(poi.name)"]
        parts.append(contentsOf: images.compactMap(\.caption))
        if let credit = poi.imageCredit {
            parts.append("Bildnachweis: \(credit)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Kopf

    /// Name und Distanz oben, mit deutlichem Abstand darunter Kategorie und
    /// Adresse – der Titel soll nicht an der Adresse kleben (Entwurf).
    private var header: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.Space.m) {
                Text(poi.name)
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColor.textBrand)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppMetrics.Space.s)

                distanceLabel
            }

            VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accessStatusLine
            }
        }
    }

    /// Distanz mit Richtungspfeil, wie im Entwurf ohne Kapsel.
    private var distanceLabel: some View {
        HStack(spacing: AppMetrics.Space.s) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 15, weight: .regular))
                .rotationEffect(.degrees(45))
            Text(DistanceFormatter.string(fromMeters: poi.distanceM))
                .font(AppTypography.body)
                .monospacedDigit()
        }
        .foregroundStyle(AppColor.accentPrimary)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DistanceFormatter.awayString(fromMeters: poi.distanceM))
    }

    /// Kategorie und Adresse, getrennt durch einen senkrechten Strich (Entwurf).
    private var headerSubtitle: String? {
        let address = poi.placeAddressLine ?? poi.address
        let parts = [poi.categoryDisplayName, address].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    /// Zugänglichkeit in einer Zeile: mit ginto-Bewertung als Prozentwert,
    /// sonst als Status. Symbol plus Text – nie allein über die Farbe.
    private var accessStatusLine: some View {
        let rating = poi.gintoRating(for: profile.wheelchairType)
        let status = rating?.status ?? poi.accessStatus
        let text: String = {
            if let percent = rating?.conformancePercent {
                return "Zu \(Int(percent))% zugänglich für dich"
            }
            return status.label
        }()

        return HStack(spacing: AppMetrics.Space.s) {
            Image(systemName: status.symbolName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(status.tint)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(AppColor.borderDecorative)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: - Aktionen

    /// Drei gleich breite Kacheln: AR-Route als Hauptaktion, daneben Route und
    /// Speichern in der gedämpften Variante (Entwurf).
    private var actionRow: some View {
        HStack(spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            actionTile(
                icon: "camera.viewfinder",
                title: "AR-Route",
                isPrimary: true,
                disabled: onStartARRoute == nil,
                accessibilityHint: onStartARRoute == nil
                    ? "Noch nicht verfügbar"
                    : "Berechnet die rollstuhlgerechte Route und zeigt sie im Kamerabild"
            ) {
                guard let onStartARRoute else { return }
                dismiss()
                onStartARRoute(poi)
            }

            actionTile(
                icon: "map",
                title: "Route",
                accessibilityHint: onShowRoute == nil
                    ? "Öffnet die Route in Apple Karten"
                    : "Berechnet die rollstuhlgerechte Route und zeigt sie auf der Karte"
            ) {
                if let onShowRoute {
                    dismiss()
                    onShowRoute(poi)
                } else {
                    openInMaps()
                }
            }

            actionTile(
                icon: saveIcon,
                title: saveTitle,
                loading: saveState == .saving,
                disabled: saveState == .saving || saveState == .saved,
                action: savePlace
            )
        }
    }

    /// Kachel mit Symbol über der Beschriftung.
    private func actionTile(
        icon: String,
        title: String,
        isPrimary: Bool = false,
        loading: Bool = false,
        disabled: Bool = false,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppMetrics.Space.s) {
                ZStack {
                    if loading {
                        ProgressView()
                            .tint(isPrimary ? AppColor.onAccent : AppColor.accentPrimary)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .regular))
                    }
                }
                .frame(height: 26)

                Text(title)
                    .font(AppTypography.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .padding(.horizontal, AppMetrics.Space.s)
            .foregroundStyle(isPrimary ? AppColor.onAccent : AppColor.accentPrimary)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.sheet, style: .continuous)
                    .fill(isPrimary ? AppColor.accentPrimary : AppColor.accentMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.sheet, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.6 : 1)
        .disabled(disabled)
        .accessibilityHint(accessibilityHint ?? "")
    }

    /// Icon der Speichern-Kachel je nach Zustand.
    private var saveIcon: String {
        switch saveState {
        case .idle, .saving: return "bookmark"
        case .saved:         return "bookmark.fill"
        case .failed:        return "exclamationmark.triangle"
        }
    }

    private var saveTitle: String {
        switch saveState {
        case .idle:   return "Speichern"
        case .saving: return "Speichern…"
        case .saved:  return "Gespeichert"
        case .failed: return "Fehlgeschlagen"
        }
    }

    // MARK: - Über den Ort

    /// Beschreibung aus dem Tourismus-API: der Einzeiler als Aufhänger, darunter
    /// der ausführliche Text.
    @ViewBuilder
    private var aboutSection: some View {
        let summary = poi.placeSummary
        let description = poi.placeDescription ?? poi.placeTeaser

        if summary != nil || description != nil {
            VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
                Text("Über diesen Ort")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textBrand)
                    .accessibilityAddTraits(.isHeader)

                // Aufhänger und ausführlicher Text sind ein Fliesstext: gleiche
                // Schriftfarbe, gleicher Zeilenabstand (Styleguide §3, 1,5-fach).
                if let summary {
                    Text(summary)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let description, description != summary {
                    Text(description)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Stichpunkte zum Ort («Grosse Terrasse», «Blick auf die Altstadt»).
    @ViewBuilder
    private var highlightsSection: some View {
        let items = poi.highlights
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                            .padding(.top, 3)
                        Text(item)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(AppMetrics.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Besonderheiten: " + items.joined(separator: ", "))
        }
    }

    // MARK: - Öffnungszeiten

    /// Öffnungszeiten mit Symbolkreis links (Entwurf). Zuoberst der heutige
    /// Tag, darunter eine Zeile je Wochentag – immer auf Deutsch und immer in
    /// derselben Form: «Mo: 08:00 – 12:00 Uhr» (siehe OpeningHoursFormatter).
    private var openingHoursCard: some View {
        let hours = poi.openingHoursLines
        let today = poi.openingHoursToday()

        return HStack(alignment: .top, spacing: AppMetrics.Space.m) {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(AppColor.accentMuted, in: Circle())

            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                Text("Öffnungszeiten")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textBrand)

                if let today {
                    Text("Heute: \(today) Uhr")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                if hours.isEmpty {
                    Text("Für diesen Ort liegen keine Öffnungszeiten vor.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(hours, id: \.self) { line in
                        Text(line)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Kontakt

    /// Telefon, E-Mail, Webseite und Preisniveau – alles, was das API an
    /// praktischen Angaben liefert.
    @ViewBuilder
    private var contactSection: some View {
        let rows = contactRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    contactRow(row)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(AppColor.borderDecorative)
                            .frame(height: 1)
                            .padding(.leading, 44 + AppMetrics.Space.m + AppMetrics.Space.m)
                    }
                }
            }
            .background(
                AppColor.surfaceTinted,
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            )
        }
    }

    private struct ContactRow {
        let icon: String
        let title: String
        let value: String
        var url: URL?
    }

    private var contactRows: [ContactRow] {
        var rows: [ContactRow] = []
        if let number = poi.phoneNumber {
            rows.append(ContactRow(icon: "phone.fill", title: "Telefon", value: number, url: poi.phoneURL))
        }
        if let mail = poi.emailAddress {
            rows.append(ContactRow(icon: "envelope.fill", title: "E-Mail", value: mail, url: poi.emailURL))
        }
        if let url = poi.websiteURL {
            rows.append(ContactRow(icon: "safari", title: "Webseite", value: cleanHost(url), url: url))
        }
        if let price = poi.priceRange {
            rows.append(ContactRow(icon: "swissfranc", title: "Preisniveau", value: price))
        }
        return rows
    }

    @ViewBuilder
    private func contactRow(_ row: ContactRow) -> some View {
        if let url = row.url {
            Link(destination: url) {
                contactRowContent(row, showsChevron: true)
            }
            .accessibilityLabel("\(row.title): \(row.value)")
        } else {
            contactRowContent(row, showsChevron: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func contactRowContent(_ row: ContactRow, showsChevron: Bool) -> some View {
        HStack(spacing: AppMetrics.Space.m) {
            Image(systemName: row.icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(AppColor.accentMuted, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textBrand)
                Text(row.value)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppMetrics.Space.s)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppMetrics.Space.m)
        .frame(minHeight: AppMetrics.Touch.primary)
    }

    /// Host einer URL ohne Schema und führendes «www.».
    private func cleanHost(_ url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    // MARK: - Eurokey (nur wenn die POI-Daten Eurokey erwähnen)

    @ViewBuilder
    private var eurokeyHint: some View {
        if mentionsEurokey {
            let ok = profile.hasEurokey
            let tint = ok ? AppColor.Status.openIcon : AppColor.Status.limitedIcon
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                Image(systemName: "key.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                Text(ok
                     ? "Mit deinem Eurokey zugänglich"
                     : "Eurokey erforderlich")
                    .font(AppTypography.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.Space.m)
            .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.field, style: .continuous)
            )
        }
    }

    private var mentionsEurokey: Bool {
        guard let details = poi.accessibilityDetails else { return false }
        for (key, value) in details {
            if key.lowercased().contains("eurokey") { return true }
            if case .string(let s) = value, s.lowercased().contains("eurokey") { return true }
        }
        return false
    }

    /// Quellenangabe und Stand der übernommenen Angaben.
    @ViewBuilder
    private var infoSourceNote: some View {
        if let credit = poi.infoCredit {
            Text(sourceText(credit))
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceText(_ credit: String) -> String {
        guard let updated = poi.infoUpdatedAt else { return "Angaben: \(credit)" }
        let date = updated.formatted(.dateTime.locale(.appGerman).day().month(.wide).year())
        return "Angaben: \(credit) · Stand \(date)"
    }

    // MARK: - Aktionen

    private func savePlace() {
        saveState = .saving
        Task {
            do {
                try await SavedPlacesService.shared.save(poi: poi)
                saveState = .saved
            } catch {
                saveState = .failed
            }
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: poi.latitude,
            longitude: poi.longitude
        ))
        let item = MKMapItem(placemark: placemark)
        item.name = poi.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}