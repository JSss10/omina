// POIDetailSheet.swift
// Omina
//
// POI-Detail als Bottom-Sheet: Name, Kategorie, Adresse, Distanz, Fotos,
// Zugänglichkeits-Status fürs Profil, Bewertung für den eigenen
// Rollstuhltyp, Detail-Werte aus accessibility_details, Webseite und
// Aktionen (Route mit Kamera starten, Ort speichern, Route auf der Karte anzeigen).
//
// Styling gemäss Styleguide v1.0: ausschliesslich Design-Tokens (AppColor,
// AppTypography, AppMetrics) und die gemeinsamen Komponenten (StatusBadge,
// App-Button-Stile). Aufbau in klar getrennten, angehobenen Karten.

import SwiftUI
import MapKit
import Supabase

struct POIDetailSheet: View {
    let poi: POI
    /// Profil des Users – bestimmt, welche ginto-Bewertung angezeigt wird
    /// (nur der eigene Rollstuhltyp, nicht alle Profile).
    let profile: UserProfile
    /// Startet die AR-Navigation zu diesem POI. Ohne Callback bleibt der
    /// Button deaktiviert (Kontext ohne AR-Zugang).
    var onStartARRoute: ((POI) -> Void)? = nil
    /// Berechnet die Route in-App und zeigt sie auf der Karte. Ohne Callback
    /// öffnet "Route anzeigen" als Fallback Apple Maps.
    var onShowRoute: ((POI) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var saveState: SaveState = .idle
    @State private var photoIndex = 0

    enum SaveState {
        case idle, saving, saved, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                header
                photoCarousel
                descriptionText
                eurokeyHint
                // Zugänglichkeit zuerst, danach die praktischen Angaben aus
                // dem Zürich-Tourismus-API (Zeiten, Kontakt, Webseite).
                ratingsCard
                accessStatusLine
                openingHoursCard
                detailsCard
                phoneRow
                websiteRow
                infoSourceNote

                VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    arButton
                    actionRow
                }
                .padding(.top, AppMetrics.Space.xs)
            }
            .padding(AppMetrics.Space.l)
        }
        .background(AppColor.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AppMetrics.Radius.sheet + AppMetrics.Space.s)
    }

    // MARK: - Eurokey (Quick Win): nur wenn die POI-Daten Eurokey erwähnen.
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

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.Space.m) {
                Text(poi.name)
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppMetrics.Space.s)
                distanceChip
            }

            if let subtitle = headerSubtitle {
                Text(subtitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var distanceChip: some View {
        HStack(spacing: AppMetrics.Space.xs) {
            Image(systemName: "location.fill")
                .font(.caption2.weight(.bold))
            Text(DistanceFormatter.string(fromMeters: poi.distanceM))
                .font(AppTypography.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(AppColor.accentPrimary)
        .padding(.horizontal, AppMetrics.Space.s + AppMetrics.Space.xs)
        .padding(.vertical, AppMetrics.Space.xs + 2)
        .background(AppColor.Violet.v100, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DistanceFormatter.awayString(fromMeters: poi.distanceM))
    }

    /// Kategorie (deutscher ginto-Name) und Adresse, soweit vorhanden.
    private var headerSubtitle: String? {
        let parts = [poi.categoryDisplayName, poi.address].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Foto-Karussell des Ortes als vollbreites Hero-Bild, darunter der
    /// Bildnachweis. Bei mehreren Bildern paged mit dezenten Indikatoren.
    /// Kennt das Zürich-Tourismus-API den Ort nicht, steht hier ein Platzhalter.
    @ViewBuilder
    private var photoCarousel: some View {
        let images = poi.images
        if images.isEmpty {
            photoPlaceholder
        } else {
            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                Group {
                    if images.count == 1 {
                        photo(images[0])
                    } else {
                        TabView(selection: $photoIndex) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                                photo(image).tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(AppColor.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
                // Nur ein Label auf dem Container – die Seiten des Karussells
                // bleiben für VoiceOver einzeln bedienbar.
                .accessibilityLabel(photoAccessibilityLabel(images))

                // Bildunterschrift und Quellenangabe unter dem Bild statt als
                // Overlay – sonst läge sie hinter den Seiten-Indikatoren.
                // Die Nennung der Quelle verlangt die Lizenz der Bildquelle.
                if let line = photoCaptionLine(images) {
                    Text(line)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Platzhalter, wenn zum Ort kein Foto vorliegt. Bewusst flacher als das
    /// Karussell – eine leere Fläche in voller Höhe würde das Sheet dominieren.
    private var photoPlaceholder: some View {
        VStack(spacing: AppMetrics.Space.s) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(AppColor.textSecondary)
            Text("Kein Foto verfügbar")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                .strokeBorder(AppColor.borderDecorative, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kein Foto von \(poi.name) verfügbar")
    }

    /// Kurzbeschreibung des Ortes, sofern das Zürich-Tourismus-API eine liefert.
    @ViewBuilder
    private var descriptionText: some View {
        if let text = poi.placeDescription {
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Öffnungszeiten mit hervorgehobenem heutigem Tag. Die Karte steht auch
    /// ohne Daten – dann als Platzhalter, damit im Sheet nichts fehlt.
    private var openingHoursCard: some View {
        let hours = poi.openingHours
        let today = poi.openingHoursToday()

        return VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            HStack(spacing: AppMetrics.Space.m) {
                Image(systemName: "clock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hours.isEmpty ? AppColor.textSecondary : AppColor.accentPrimary)
                    .frame(width: 28)

                Text("Öffnungszeiten")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Spacer(minLength: AppMetrics.Space.s)

                if let today {
                    Text("Heute \(today)")
                        .font(AppTypography.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
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
            // Auf die Höhe des Icons eingerückt, damit die Zeiten unter dem
            // Titel stehen und nicht unter dem Symbol beginnen.
            .padding(.leading, 28 + AppMetrics.Space.m)
        }
        .padding(AppMetrics.Space.m)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }

    /// Telefonnummer als eigene Zeile – vorab anrufen ist im Rollstuhl-Alltag
    /// oft der schnellste Weg, offene Fragen zur Zugänglichkeit zu klären.
    @ViewBuilder
    private var phoneRow: some View {
        if let number = poi.phoneNumber, let url = poi.phoneURL {
            linkRow(
                icon: "phone.fill",
                title: "Telefon",
                value: number,
                url: url,
                accessibilityLabel: "Anrufen, \(number)"
            )
        }
    }

    /// Quellenangabe für die übernommenen Text- und Kontaktangaben.
    @ViewBuilder
    private var infoSourceNote: some View {
        if let credit = poi.infoCredit {
            Text("Angaben: \(credit)")
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bildunterschrift des gerade sichtbaren Fotos plus Bildnachweis,
    /// z. B. «Saal im Literaturhaus · Foto: Zürich Tourismus (zuerich.com)».
    private func photoCaptionLine(_ images: [POIImage]) -> String? {
        let current = images.indices.contains(photoIndex) ? images[photoIndex] : images.first
        let credit = current?.credit ?? poi.imageCredit
        let parts = [current?.caption, credit.map { "Foto: \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Ein Sammel-Label statt vieler Einzelbilder: VoiceOver liest die
    /// Anzahl, die Bildunterschriften und den Bildnachweis am Stück.
    private func photoAccessibilityLabel(_ images: [POIImage]) -> String {
        var parts = [images.count == 1 ? "Foto von \(poi.name)"
                                       : "\(images.count) Fotos von \(poi.name)"]
        parts.append(contentsOf: images.compactMap(\.caption))
        if let credit = poi.imageCredit {
            parts.append("Bildnachweis: \(credit)")
        }
        return parts.joined(separator: ", ")
    }

    private func photo(_ image: POIImage) -> some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let loaded):
                loaded
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(AppColor.textSecondary)
            default:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Zugänglichkeits-Status nur als Rückfall, wenn es keine Rollstuhl-
    /// Bewertung gibt – sonst trägt die Bewertungskarte den Status und ein
    /// zusätzlicher Gesamt-Status wäre doppelt.
    @ViewBuilder
    private var accessStatusLine: some View {
        if poi.gintoRating(for: profile.wheelchairType) == nil {
            let status = poi.accessStatus
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                Image(systemName: status.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.tint)
                Text(status.label)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.Space.m)
            .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
            .background(
                status.tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppMetrics.Radius.field, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.label)
        }
    }

    /// ginto-Bewertung für den eigenen Rollstuhltyp mit Einstufung und
    /// erfüllten Kriterien in Prozent. Bewertungen anderer Profile werden
    /// bewusst nicht angezeigt.
    @ViewBuilder
    private var ratingsCard: some View {
        if let rating = poi.gintoRating(for: profile.wheelchairType) {
            // Ohne separaten «Zugänglichkeit im Detail»-Titel: die Einstufung
            // steht in der Kopfzeile, der Fortschrittsbalken mit dem Prozentwert
            // sitzt direkt darunter.
            VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
                HStack(spacing: AppMetrics.Space.m) {
                    Image(systemName: rating.status.symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(rating.status.tint)
                        .frame(width: 28)

                    // Konkreter Rollstuhltyp des Users statt der generischen
                    // Beschriftung «Dein Rollstuhltyp».
                    Text(profile.wheelchairType.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Spacer(minLength: AppMetrics.Space.s)

                    Text(rating.gradeLabel)
                        .font(AppTypography.subheadline.weight(.semibold))
                        .foregroundStyle(rating.status.tint)
                        .multilineTextAlignment(.trailing)
                }

                if let percent = rating.conformancePercent {
                    conformanceBar(percent: percent, tint: rating.status.tint)
                }
            }
            .padding(AppMetrics.Space.m)
            .cardBackground()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(profile.wheelchairType.displayName): \(rating.gradeLabel)"
                + (rating.conformancePercent.map { ", \(Int($0)) Prozent erfüllt" } ?? ""))
        }
    }

    /// Fortschrittsbalken für den erfüllten Kriterien-Anteil, mit dem Prozentwert
    /// rechts daneben – direkt unter der Einstufung.
    private func conformanceBar(percent: Double, tint: Color) -> some View {
        HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            GeometryReader { geo in
                let fraction = max(0, min(1, percent / 100))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.borderDecorative)
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text("\(Int(percent)) %")
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var detailsCard: some View {
        if let details = poi.accessibilityDetails, !details.isEmpty {
            let rows = details.keys.sorted().compactMap { key -> (String, String)? in
                // URL-/Webseiten-Felder werden separat als «Webseite»-Zeile
                // gezeigt (websiteRow), Bildfelder als Foto-Karussell mit
                // Bildnachweis; interne Quell-Schlüssel bleiben aussen vor.
                guard !isShownElsewhere(key) else { return nil }
                guard let text = displayValue(details[key]) else { return nil }
                return (key, text)
            }
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: AppMetrics.Space.m) {
                            Text(displayKey(row.0))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer(minLength: AppMetrics.Space.m)
                            Text(row.1)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, AppMetrics.Space.m)
                        .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(AppColor.borderDecorative)
                                .frame(height: 0.5)
                                .padding(.leading, AppMetrics.Space.m)
                        }
                    }
                }
                .cardBackground()
            }
        }
    }

    /// Webseite des Ortes als eigene, angehobene Zeile mit sauber gekürzter
    /// Adresse (ohne Schema/«www.»). Öffnet die Seite im Browser.
    @ViewBuilder
    private var websiteRow: some View {
        if let url = poi.websiteURL {
            linkRow(
                icon: "safari",
                title: "Webseite",
                value: cleanHost(url),
                url: url,
                accessibilityLabel: "Webseite öffnen, \(cleanHost(url))"
            )
        }
    }

    /// Angehobene Zeile mit Icon, Titel und Wert, die einen Link öffnet –
    /// gemeinsame Form für Telefon und Webseite.
    private func linkRow(
        icon: String,
        title: String,
        value: String,
        url: URL,
        accessibilityLabel: String
    ) -> some View {
        Link(destination: url) {
            HStack(spacing: AppMetrics.Space.m) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(value)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppMetrics.Space.s)

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(AppMetrics.Space.m)
            .cardBackground()
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// Host einer URL ohne Schema und führendes «www.» – für eine ruhige,
    /// lesbare Darstellung (z. B. «beispiel.ch» statt «https://www.beispiel.ch/»).
    private func cleanHost(_ url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    /// Schlüssel, die die Detail-Tabelle auslässt, weil sie an anderer Stelle
    /// stehen: Webseiten/URLs als websiteRow, Fotos am Karussell, Zeiten in
    /// der Öffnungszeiten-Karte, Telefon als eigene Zeile. `zuerich_name`
    /// dient nur der Nachvollziehbarkeit des Imports.
    private func isShownElsewhere(_ key: String) -> Bool {
        let handled: Set<String> = [
            "website", "homepage",
            "images", "image_source",
            "opening_hours", "opening_hours_spec",
            "phone", "description",
            "info_source", "zuerich_name",
        ]
        let k = key.lowercased()
        return k.contains("url") || handled.contains(k)
    }

    private var arButton: some View {
        Button {
            guard let onStartARRoute else { return }
            dismiss()
            onStartARRoute(poi)
        } label: {
            Label("Route mit Kamera starten", systemImage: "camera.viewfinder")
        }
        .buttonStyle(.appPrimary)
        .disabled(onStartARRoute == nil)
        .opacity(onStartARRoute == nil ? 0.5 : 1)
        .accessibilityHint(
            onStartARRoute == nil
                ? "Noch nicht verfügbar"
                : "Berechnet die rollstuhlgerechte Route und zeigt sie im Kamerabild"
        )
    }

    /// Zwei gleichwertige Sekundär-Aktionen als Kacheln (Icon über Label):
    /// «Ort speichern» getönt, «Route anzeigen» als Umriss.
    private var actionRow: some View {
        HStack(spacing: AppMetrics.Space.m) {
            actionTile(
                icon: saveIcon,
                title: saveTitle,
                style: .tinted,
                loading: saveState == .saving,
                disabled: saveState == .saving || saveState == .saved,
                action: savePlace
            )

            actionTile(
                icon: "map.fill",
                title: "Route anzeigen",
                style: .outline,
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
        }
    }

    /// Optische Ausprägung einer Aktions-Kachel.
    private enum ActionTileStyle {
        case tinted, outline
    }

    /// Icon-über-Label-Kachel als sekundäre Aktion. Volle Breite, gleiche Höhe,
    /// grosszügige Tap-Fläche; getönt oder als Umriss.
    private func actionTile(
        icon: String,
        title: String,
        style: ActionTileStyle,
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
                    } else {
                        Image(systemName: icon)
                            .font(.title3.weight(.semibold))
                    }
                }
                .frame(height: 26)

                Text(title)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .padding(.horizontal, AppMetrics.Space.s)
            .foregroundStyle(AppColor.accentPrimary)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .fill(style == .tinted ? AnyShapeStyle(AppColor.Violet.v100) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.button, style: .continuous)
                    .strokeBorder(
                        AppColor.accentPrimary.opacity(style == .outline ? 1 : 0),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.6 : 1)
        .disabled(disabled)
        .accessibilityHint(accessibilityHint ?? "")
    }

    /// Icon der «Ort speichern»-Kachel je nach Speicherzustand.
    private var saveIcon: String {
        switch saveState {
        case .idle:   return "bookmark"
        case .saving: return "bookmark"
        case .saved:  return "bookmark.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Beschriftung der «Ort speichern»-Kachel je nach Speicherzustand.
    private var saveTitle: String {
        switch saveState {
        case .idle:   return "Ort speichern"
        case .saving: return "Speichern…"
        case .saved:  return "Gespeichert"
        case .failed: return "Fehlgeschlagen"
        }
    }

    // MARK: - Actions

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

    // MARK: - Detail Formatting

    /// Bekannte ginto/OSM-Schlüssel eingedeutscht; Rest als Fallback roh.
    private func displayKey(_ key: String) -> String {
        switch key.lowercased() {
        case "door_width", "doorwidth":   return "Türbreite"
        case "entrance", "entry":         return "Eingang"
        case "wc", "toilet", "restroom":  return "WC"
        case "ramp":                      return "Rampe"
        case "elevator", "lift":          return "Aufzug"
        case "parking":                   return "Parkplatz"
        case "email":                     return "E-Mail"
        case "price_range":               return "Preisniveau"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func displayValue(_ value: AnyJSON?) -> String? {
        switch value {
        case .string(let s): return s
        case .double(let d): return d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
        case .integer(let i): return "\(i)"
        case .bool(let b):   return b ? "ja" : "nein"
        default:             return nil
        }
    }
}

// MARK: - Card helper

private extension View {
    /// Angehobene Kartenfläche gemäss Styleguide (SurfaceRaised, Card-Radius,
    /// dezente Kontur für Abgrenzung auch im hellen Modus).
    func cardBackground() -> some View {
        self
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                    .fill(AppColor.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
                    .strokeBorder(AppColor.borderDecorative, lineWidth: 0.5)
            )
    }
}