// WeatherDetailSheet.swift
// Omina
//
// Wetterdetails zum Tippen auf die Wetterkapsel des Homescreens. Auf dem
// Homescreen selbst steht nur die Temperatur – hier kommen die Angaben dazu,
// die im Rollstuhl-Alltag über die Wegplanung entscheiden: gefühlte
// Temperatur, UV-Index (Sonnenschutz auf offenen Plätzen), Luftfeuchtigkeit
// und Wind.
//
// Styling wie die Karten-Sheets (SheetHeader, getönte Karte, Tokens).

import SwiftUI

struct WeatherDetailSheet: View {
    let weather: CurrentWeather?
    /// Ort, für den das Wetter gilt (Reverse-Geocoding), sonst nil.
    var placeName: String?
    /// Meldung, wenn sich das Wetter nicht laden liess.
    var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Wetter", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    if let weather {
                        summary(weather)
                        detailsCard(weather)
                        note
                    } else {
                        unavailable
                    }
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.top, AppMetrics.Space.s)
                .padding(.bottom, AppMetrics.Space.xl)
            }
        }
        .background(AppColor.surfaceOverlay)
        .presentationBackground(AppColor.surfaceOverlay)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AppMetrics.Radius.sheet + AppMetrics.Space.s)
    }

    // MARK: - Kopf

    /// Temperatur gross, daneben das Wettersymbol; darunter Zustand und Ort.
    private func summary(_ weather: CurrentWeather) -> some View {
        HStack(alignment: .center, spacing: AppMetrics.Space.m) {
            VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                Text(temperatureText(weather.temperatureC))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColor.textBrand)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(weather.conditionDescription)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textPrimary)

                if let placeName {
                    Text(placeName)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: AppMetrics.Space.s)

            Image(systemName: weather.symbolName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 72, height: 72)
                .background(AppColor.accentPrimary, in: Circle())
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityText(weather))
    }

    private func summaryAccessibilityText(_ weather: CurrentWeather) -> String {
        var parts = ["\(Int(weather.temperatureC.rounded())) Grad", weather.conditionDescription]
        if let placeName { parts.append("in \(placeName)") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Werte

    private func detailsCard(_ weather: CurrentWeather) -> some View {
        VStack(spacing: 0) {
            let rows = detailRows(weather)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                detailRow(row)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(AppColor.borderDecorative)
                        .frame(height: 1)
                        .padding(.leading, 40 + AppMetrics.Space.m + AppMetrics.Space.m)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(
            AppColor.surfaceTinted,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
    }

    private struct DetailRow {
        let symbol: String
        let title: String
        let value: String
    }

    private func detailRows(_ weather: CurrentWeather) -> [DetailRow] {
        [
            DetailRow(
                symbol: "thermometer.medium",
                title: "Gefühlt",
                value: temperatureText(weather.feelsLikeC)
            ),
            DetailRow(
                symbol: "sun.max.trianglebadge.exclamationmark",
                title: "UV-Index",
                value: "\(Int(weather.uvIndex.rounded())) · \(weather.uvCategory)"
            ),
            DetailRow(
                symbol: "humidity",
                title: "Luftfeuchtigkeit",
                value: "\(weather.humidityPercent) %"
            ),
            DetailRow(
                symbol: "wind",
                title: "Wind",
                value: "\(Int(weather.windSpeedKmh.rounded())) km/h"
            )
        ]
    }

    private func detailRow(_ row: DetailRow) -> some View {
        HStack(spacing: AppMetrics.Space.m) {
            SheetRowIcon(symbol: row.symbol)

            Text(row.title)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textPrimary)

            Spacer(minLength: AppMetrics.Space.s)

            Text(row.value)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textBrand)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppMetrics.Space.m)
        .padding(.vertical, AppMetrics.Space.s + AppMetrics.Space.xs)
        .frame(minHeight: AppMetrics.Touch.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title): \(row.value)")
    }

    /// Kurze Einordnung: Warum das Wetter auf dem Homescreen steht.
    private var note: some View {
        Text("Hitze, Nässe und starker Wind machen manche Wege beschwerlicher. Plane bei hohem UV-Index Schattenpausen ein.")
            .font(AppTypography.footnote)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Ohne Daten

    private var unavailable: some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.m) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(AppColor.accentMuted, in: Circle())

            Text(errorMessage ?? "Das Wetter ist gerade nicht verfügbar.")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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

    private func temperatureText(_ celsius: Double) -> String {
        "\(Int(celsius.rounded())) °C"
    }
}

#Preview {
    WeatherDetailSheet(
        weather: CurrentWeather(
            temperatureC: 23,
            feelsLikeC: 21,
            humidityPercent: 58,
            uvIndex: 6.2,
            windSpeedKmh: 12,
            weatherCode: 2,
            isDay: true
        ),
        placeName: "Zürich"
    )
}