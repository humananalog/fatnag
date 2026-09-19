import Charts
import SwiftUI

/// History: Apple Health weight + body fat charts, optional Trend projection, Manual entry.
///
/// Layout contract: content-first VStack; atmosphere is `.background` only so
/// oversized decorations cannot widen the sheet and clip mid-word labels.
struct WeighInResultsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var range: HealthHistoryRange = .default
    @State private var showTrend = false
    @State private var chartReveal = false
    @State private var loadError: String?
    @State private var selectedWeightDate: Date?
    @State private var selectedFatDate: Date?

    private let horizontalInset: CGFloat = 24
    private let panelInnerPad: CGFloat = 14

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    private var weightProjection: WeightTrendProjection? {
        guard showTrend else { return nil }
        return HealthChartMath.projectWeightToIdeal(
            windowSamples: session.historyTrendWindowWeights,
            idealKg: session.profile.idealWeightKg
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            controlsRow
                .padding(.top, 10)
                .padding(.bottom, 8)

            if let loadError {
                Text(loadError)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                chartsColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            TrendAtmosphereBackground(atmosphere: atmosphere)
                .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: range)
        .task(id: range) {
            await reload(for: range)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
                chartReveal = true
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.isManualEntryPresented },
            set: { if !$0 { session.dismissManualEntry() } }
        )) {
            ManualWeighInView()
                .environmentObject(session)
        }
    }

    private var historyTitle: String {
        let name = session.profile.greetingName
        return name.isEmpty ? "History" : "\(name)'s History"
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                session.dismissResults()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close history")

            VStack(alignment: .leading, spacing: 2) {
                Text(historyTitle)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(atmosphere.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Apple Health")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                session.presentManualEntry()
            } label: {
                Text("Manual")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(atmosphere.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Manual weight entry")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }

    private var controlsRow: some View {
        VStack(spacing: 10) {
            Picker("Range", selection: $range) {
                ForEach(HealthHistoryRange.allCases) { item in
                    Text(item.title)
                        .accessibilityLabel(item.accessibilityTitle)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: range) { _, _ in
                selectedWeightDate = nil
                selectedFatDate = nil
                chartReveal = false
                withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                    chartReveal = true
                }
            }

            HStack(spacing: 10) {
                Toggle(isOn: $showTrend.animation(.spring(response: 0.7, dampingFraction: 0.84))) {
                    Text("Trend")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.85))
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Trend projection to ideal weight")

                Text("Trend")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))

                if showTrend, let projection = weightProjection {
                    Text(trendCaption(projection))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    private var chartsColumn: some View {
        let projection = weightProjection
        let projectedValues = projection?.path.map(\.value) ?? []

        return VStack(spacing: 12) {
            weightChartCard(projection: projection, projectedValues: projectedValues)
            bodyFatChartCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(chartReveal ? 1 : 0.2)
        .offset(y: chartReveal ? 0 : 10)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: chartReveal)
        .animation(.spring(response: 0.75, dampingFraction: 0.84), value: showTrend)
        .animation(.spring(response: 0.65, dampingFraction: 0.88), value: session.historyWeights.count)
    }

    private func weightChartCard(
        projection: WeightTrendProjection?,
        projectedValues: [Double]
    ) -> some View {
        let samples = session.historyWeights
        let extrema = HealthChartMath.extrema(in: samples)
        let domain = HealthChartMath.weightDomain(
            values: samples.map(\.value),
            idealKg: session.profile.idealWeightKg,
            extraValues: projectedValues
        )
        let xDomain = weightXDomain(samples: samples, projection: projection)
        let selected = selectedWeightDate.flatMap {
            HealthChartMath.nearestSample(in: samples, to: $0)
        }

        return metricScaffold(
            title: "Weight",
            unit: "kg",
            samples: samples,
            extrema: extrema,
            formatValue: { String(format: "%.1f", $0) },
            emptyCopy: "No weight samples in this range."
        ) {
            Chart {
                RuleMark(y: .value("Ideal", session.profile.idealWeightKg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(atmosphere.accent.opacity(0.45))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ideal")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.accent.opacity(0.55))
                            .padding(.trailing, 2)
                    }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value),
                        series: .value("Series", "Health")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(atmosphere.accent.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [atmosphere.accent.opacity(0.22), atmosphere.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value)
                    )
                    .symbolSize(selected?.id == sample.id ? 72 : 28)
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                }

                if let projection, showTrend {
                    ForEach(Array(projection.path.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.value),
                            series: .value("Series", "Trend")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(atmosphere.accent.opacity(0.55))
                        .interpolationMethod(.linear)
                    }

                    if let crossing = projection.crossing {
                        PointMark(
                            x: .value("Date", crossing.date),
                            y: .value("Weight", crossing.value)
                        )
                        .symbolSize(64)
                        .foregroundStyle(atmosphere.accent)
                        .annotation(position: .top, spacing: 6) {
                            VStack(spacing: 2) {
                                Text(crossing.date, format: .dateTime.month(.abbreviated).day().year())
                                Text(String(format: "%.1f kg", crossing.value))
                            }
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(atmosphere.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                if let selected {
                    RuleMark(x: .value("Selected", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(atmosphere.accent.opacity(0.35))
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Weight", selected.value)
                    )
                    .symbolSize(90)
                    .foregroundStyle(atmosphere.accent)
                    .annotation(position: .top, spacing: 6) {
                        Text(String(format: "%.1f kg", selected.value))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(atmosphere.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.8), in: Capsule())
                    }
                }

                if let extrema, selected == nil {
                    extremaMarks(extrema: extrema, title: "Weight", formatValue: { String(format: "%.1f", $0) })
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $selectedWeightDate)
            .historyChartScroll(for: range)
            .chartGestureStyle()
        }
    }

    private var bodyFatChartCard: some View {
        let samples = session.historyBodyFatPercents
        let extrema = HealthChartMath.extrema(in: samples)
        let domain = HealthChartMath.bodyFatDomain(
            values: samples.map(\.value),
            idealPercent: session.profile.idealBodyFatPercent
        )
        let selected = selectedFatDate.flatMap {
            HealthChartMath.nearestSample(in: samples, to: $0)
        }

        return metricScaffold(
            title: "Body fat",
            unit: "%",
            samples: samples,
            extrema: extrema,
            formatValue: { String(format: "%.1f", $0) },
            emptyCopy: "No body fat samples in this range."
        ) {
            Chart {
                if let ideal = session.profile.idealBodyFatPercent {
                    RuleMark(y: .value("Ideal", ideal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(atmosphere.accent.opacity(0.45))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ideal")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(atmosphere.accent.opacity(0.55))
                                .padding(.trailing, 2)
                        }
                }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Body fat", sample.value),
                        series: .value("Series", "Health")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(atmosphere.accent.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Date", sample.date),
                        y: .value("Body fat", sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [atmosphere.accent.opacity(0.22), atmosphere.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Date", sample.date),
                        y: .value("Body fat", sample.value)
                    )
                    .symbolSize(selected?.id == sample.id ? 72 : 28)
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                }

                if let selected {
                    RuleMark(x: .value("Selected", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(atmosphere.accent.opacity(0.35))
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Body fat", selected.value)
                    )
                    .symbolSize(90)
                    .foregroundStyle(atmosphere.accent)
                    .annotation(position: .top, spacing: 6) {
                        Text(String(format: "%.1f%%", selected.value))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(atmosphere.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.8), in: Capsule())
                    }
                }

                if let extrema, selected == nil {
                    extremaMarks(extrema: extrema, title: "Body fat", formatValue: { String(format: "%.1f", $0) })
                }
            }
            .chartYScale(domain: domain)
            .chartXSelection(value: $selectedFatDate)
            .historyChartScroll(for: range)
            .chartGestureStyle()
        }
    }

    private func metricScaffold<Content: View>(
        title: String,
        unit: String,
        samples: [HealthMetricSample],
        extrema: (highest: HealthMetricSample, lowest: HealthMetricSample)?,
        formatValue: @escaping (Double) -> String,
        emptyCopy: String,
        @ViewBuilder chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.78))
                Text(unit)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.55))
                Spacer(minLength: 8)
                if let extrema {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("H \(formatValue(extrema.highest.value)) · L \(formatValue(extrema.lowest.value))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(atmosphere.accent.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let rate = HealthChartMath.ratePerWeek(samples: samples) {
                            Text(String(format: "%+.2f / wk", rate))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(atmosphere.accent.opacity(0.55))
                        }
                    }
                }
            }

            if samples.isEmpty {
                Text(emptyCopy)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                chart()
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(atmosphere.accent.opacity(0.12))
                            AxisValueLabel()
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(atmosphere.accent.opacity(0.55))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(atmosphere.accent.opacity(0.12))
                            AxisValueLabel()
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(atmosphere.accent.opacity(0.55))
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(title: title, unit: unit, samples: samples, extrema: extrema))
    }

    @ChartContentBuilder
    private func extremaMarks(
        extrema: (highest: HealthMetricSample, lowest: HealthMetricSample),
        title: String,
        formatValue: @escaping (Double) -> String
    ) -> some ChartContent {
        PointMark(
            x: .value("Date", extrema.highest.date),
            y: .value(title, extrema.highest.value)
        )
        .symbolSize(56)
        .foregroundStyle(atmosphere.accent)
        .annotation(position: .top, spacing: 4) {
            Text("H \(formatValue(extrema.highest.value))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.55), in: Capsule())
        }

        PointMark(
            x: .value("Date", extrema.lowest.date),
            y: .value(title, extrema.lowest.value)
        )
        .symbolSize(56)
        .foregroundStyle(atmosphere.accent)
        .annotation(position: .bottom, spacing: 4) {
            Text("L \(formatValue(extrema.lowest.value))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.55), in: Capsule())
        }
    }

    private func weightXDomain(
        samples: [HealthMetricSample],
        projection: WeightTrendProjection?
    ) -> ClosedRange<Date> {
        let sampleDates = samples.map(\.date)
        let projectionDates = (showTrend ? projection?.path.map(\.date) : nil) ?? []
        let all = sampleDates + projectionDates
        guard let lo = all.min(), let hi = all.max() else {
            let now = Date()
            return now.addingTimeInterval(-7 * 86_400)...now
        }
        if lo == hi {
            return lo.addingTimeInterval(-86_400)...hi.addingTimeInterval(86_400)
        }
        let pad = max(hi.timeIntervalSince(lo) * 0.04, 3_600)
        return lo.addingTimeInterval(-pad)...hi.addingTimeInterval(pad)
    }

    private func trendCaption(_ projection: WeightTrendProjection) -> String {
        if let crossing = projection.crossing {
            let day = crossing.date.formatted(.dateTime.month(.abbreviated).day())
            return String(format: "→ %.1f kg · %@", crossing.value, day)
        }
        if abs(projection.slopeKgPerDay) <= 0.001 {
            return "Flat vs ideal"
        }
        if projection.slopeKgPerDay < 0 {
            return "Losing, not aimed at ideal"
        }
        return "Gaining, not aimed at ideal"
    }

    private func accessibilityLabel(
        title: String,
        unit: String,
        samples: [HealthMetricSample],
        extrema: (highest: HealthMetricSample, lowest: HealthMetricSample)?
    ) -> String {
        guard let extrema else {
            return "\(title) chart. No samples."
        }
        return "\(title) chart in \(unit). Highest \(extrema.highest.value), lowest \(extrema.lowest.value). \(samples.count) samples."
    }

    private func reload(for range: HealthHistoryRange) async {
        loadError = nil
        do {
            try await session.loadHistory(for: range)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private extension View {
    /// Soft chart chrome without Metal `.drawingGroup` / heavy blur (avoids fopen cache spam).
    @ViewBuilder
    func chartGestureStyle() -> some View {
        self
    }

    /// Pan longer History ranges (3M / 1Y) with Charts scroll APIs from the iOS 17+ Charts stack
    /// (built against the iOS 27 SDK on this Mac).
    @ViewBuilder
    func historyChartScroll(for range: HealthHistoryRange) -> some View {
        if range.prefersHorizontalScroll {
            self
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: range.visibleDomainLength)
                .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(day: 1)))
        } else {
            self
        }
    }
}

#Preview {
    WeighInResultsView()
        .environmentObject(ScaleSessionViewModel())
}
