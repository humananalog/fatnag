import Charts
import SwiftUI
import UIKit

/// History: Apple Health weight + body fat charts, optional Trend projection, Manual entry.
///
/// Layout contract: content-first VStack; atmosphere is `.background` only so
/// oversized decorations cannot widen the sheet and clip mid-word labels.
struct WeighInResultsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var range: HealthHistoryRange = .default
    @State private var showTrend = false
    @State private var chartReveal = false
    @State private var projectionReveal = 0.0
    @State private var loadError: String?
    /// Shared across weight + body-fat charts so an X tap highlights both at once.
    @State private var selectedDate: Date?
    @State private var weightYFloorMode: HealthChartMath.ChartYFloorMode = .target
    @State private var fatYFloorMode: HealthChartMath.ChartYFloorMode = .target
    @State private var commentDraft = ""
    @State private var showCommentEditor = false
    @State private var commentMetric: ChartCommentMetric = .weight
    @State private var commentSampleDay: Date = Date()
    @State private var commentRefresh = 0

    private let horizontalInset: CGFloat = 24
    private let panelInnerPad: CGFloat = 14

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    /// Fill/line ink from the selected period's weight slope — shared by both charts.
    private var periodTone: HistoryChartTone {
        let series = HealthChartMath.chartSeries(session.historyWeights)
        return HistoryChartTone.from(ratePerWeek: HealthChartMath.ratePerWeek(samples: series))
    }

    private var periodChartAtmosphere: TrendAtmosphere { periodTone.atmosphere }
    private var chartInk: Color { periodChartAtmosphere.accent }
    private var chartMid: Color { periodChartAtmosphere.mid }

    private var weightProjection: WeightTrendProjection? {
        guard showTrend else { return nil }
        return HealthChartMath.projectWeightToIdeal(
            windowSamples: session.historyTrendWindowWeights,
            idealKg: session.profile.idealWeightKg
        )
    }

    /// Projection lines only when the History toggle is on.
    private var scientificProjection: ScientificWeightProjection? {
        guard showTrend else { return nil }
        return session.scientificWeightProjection()
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

            if selectedWeightSample != nil || selectedFatSample != nil {
                chartSelectionFooter
                    .padding(.top, 8)
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
        .onChange(of: showTrend) { _, isOn in
            selectedDate = nil
            animateProjectionReveal(isOn)
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
        .sheet(isPresented: $showCommentEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(commentMetric == .weight
                         ? AppLanguageStore.text("history.comment.weight", default: "Weight comment")
                         : AppLanguageStore.text("history.comment.body_fat", default: "Body fat comment"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(commentSampleDay, format: .dateTime.month().day().year())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField(
                        AppLanguageStore.text("history.comment.placeholder", default: "What happened that day?"),
                        text: $commentDraft,
                        axis: .vertical
                    )
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                    Text("\(commentDraft.count)/\(ChartCommentStore.maxLength)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(20)
                .navigationTitle(AppLanguageStore.text("history.add_comments", default: "Add comments"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLanguageStore.text("common.cancel", default: "Cancel")) { showCommentEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLanguageStore.text("common.save", default: "Save")) {
                            ChartCommentStore.upsert(
                                sampleDay: commentSampleDay,
                                metric: commentMetric,
                                text: String(commentDraft.prefix(ChartCommentStore.maxLength))
                            )
                            commentRefresh += 1
                            showCommentEditor = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var selectedWeightSample: HealthMetricSample? {
        selectedDate.flatMap {
            HealthChartMath.nearestSample(in: HealthChartMath.chartSeries(session.historyWeights), to: $0)
        }
    }

    private var selectedFatSample: HealthMetricSample? {
        selectedDate.flatMap {
            HealthChartMath.nearestSample(in: HealthChartMath.chartSeries(session.historyBodyFatPercents), to: $0)
        }
    }

    private var chartSelectionFooter: some View {
        let weight = selectedWeightSample
        let fat = selectedFatSample
        let _ = commentRefresh
        return VStack(spacing: 8) {
            if let weight {
                let existing = ChartCommentStore.comment(on: weight.date, metric: .weight)?.text
                Text("\(UnitFormat.massString(weight.value, system: session.preferredUnits, fractionDigits: 1)) · \(weight.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                if let existing, !existing.isEmpty {
                    Text(existing)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                        .lineLimit(2)
                }
            }
            if let fat {
                let existing = ChartCommentStore.comment(on: fat.date, metric: .bodyFat)?.text
                Text(String(format: "%.1f%% · %@", fat.value, fat.date.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                if let existing, !existing.isEmpty {
                    Text(existing)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                        .lineLimit(2)
                }
            }

            Button {
                if let weight {
                    commentMetric = .weight
                    commentSampleDay = weight.date
                    commentDraft = ChartCommentStore.comment(on: weight.date, metric: .weight)?.text ?? ""
                } else if let fat {
                    commentMetric = .bodyFat
                    commentSampleDay = fat.date
                    commentDraft = ChartCommentStore.comment(on: fat.date, metric: .bodyFat)?.text ?? ""
                }
                showCommentEditor = true
            } label: {
                Text(AppLanguageStore.text("history.add_comments", default: "Add comments"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(atmosphere.accent)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var historyTitle: String {
        let name = session.profile.greetingName
        if name.isEmpty {
            return AppLanguageStore.text("history.title", default: "History")
        }
        return String(
            format: AppLanguageStore.text("history.title.named", default: "%@'s History"),
            name
        )
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
                    .scaleGlassCircle()
            }
            .accessibilityLabel(AppLanguageStore.text("history.close", default: "Close history"))

            VStack(alignment: .leading, spacing: 2) {
                Text(historyTitle)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(atmosphere.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let analysis = session.lastWeighInAnalysis {
                    if let deltaText = analysis.deltaDisplay(system: session.preferredUnits),
                       analysis.isWinnerLoss
                    {
                        Text("\(deltaText) · \(AppLanguageStore.text("history.winner", default: "winner"))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(atmosphere.accent.opacity(0.9))
                            .lineLimit(1)
                            .accessibilityIdentifier("history.winnerDelta")
                    } else {
                        Text(analysis.headline)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(atmosphere.accent.opacity(0.8))
                            .lineLimit(1)
                    }
                } else {
                    Text(AppLanguageStore.text("history.source.health", default: "Apple Health"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                session.presentManualEntry()
            } label: {
                Text(AppLanguageStore.text("history.source.manual", default: "Manual"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(atmosphere.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .scaleGlassCapsule()
            }
            .accessibilityLabel(AppLanguageStore.text("history.manual.a11y", default: "Manual weight entry"))
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
                selectedDate = nil
                chartReveal = false
                withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                    chartReveal = true
                }
            }

            HStack(spacing: 10) {
                Toggle(isOn: $showTrend.animation(.spring(response: 0.7, dampingFraction: 0.84))) {
                    Text(AppLanguageStore.text("history.projection", default: "Projection"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.85))
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(AppLanguageStore.text("history.projection.a11y", default: "Show target projection lines"))

                Text(AppLanguageStore.text("history.projection", default: "Projection"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))

                if showTrend, let sci = scientificProjection {
                    Text(trendCaptionScientific(sci))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if showTrend, let projection = weightProjection {
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
        let scientific = scientificProjection
        let projectedValues: [Double] = {
            guard showTrend else { return [] }
            return (scientific?.temperedPath.map(\.value) ?? [])
                + (scientific?.observedPath.map(\.value) ?? [])
                + (projection?.path.map(\.value) ?? [])
        }()

        return VStack(spacing: 12) {
            weightChartCard(
                projection: projection,
                scientific: scientific,
                projectedValues: projectedValues
            )
            bodyFatChartCard
            if showTrend, let scientific, !scientific.notes.isEmpty {
                Text(scientific.methodSummary)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(chartReveal ? 1 : 0.2)
        .offset(y: chartReveal ? 0 : 10)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: chartReveal)
        .animation(.spring(response: 0.75, dampingFraction: 0.84), value: showTrend)
        .animation(.spring(response: 0.65, dampingFraction: 0.88), value: session.historyWeights.count)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: weightYFloorMode)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: fatYFloorMode)
        .animation(.easeInOut(duration: 0.35), value: periodTone)
        .animation(.easeOut(duration: 1.15), value: projectionReveal)
    }

    private func weightChartCard(
        projection: WeightTrendProjection?,
        scientific: ScientificWeightProjection?,
        projectedValues: [Double]
    ) -> some View {
        let samples = HealthChartMath.chartSeries(session.historyWeights)
        let extrema = HealthChartMath.extrema(in: samples)
        let xDomain = historyXDomain(
            projection: projection,
            scientific: scientific
        )
        let visibleValues = HealthChartMath.valuesInVisibleXWindow(
            samples: samples,
            visibleStart: xDomain.lowerBound,
            visibleLength: nil,
            xDomain: xDomain
        )
        let domain = HealthChartMath.weightDomain(
            values: visibleValues.isEmpty ? samples.map(\.value) : visibleValues,
            idealKg: session.profile.idealWeightKg,
            extraValues: projectedValues,
            floorMode: weightYFloorMode
        )
        let selected = selectedDate.flatMap {
            HealthChartMath.nearestSample(in: samples, to: $0)
        }
        let floorY = domain.lowerBound
        let targetKg = session.profile.idealWeightKg
        let lineInterpolation: InterpolationMethod = samples.count >= 2 ? .monotone : .linear
        let ink = chartInk
        let mid = chartMid

        return metricScaffold(
            title: AppLanguageStore.text("live.weight", default: "Weight"),
            unit: session.preferredUnits.massLabel,
            samples: samples,
            extrema: extrema,
            formatValue: {
                String(format: "%.1f", UnitFormat.mass(fromKg: $0, system: session.preferredUnits))
            },
            emptyCopy: AppLanguageStore.text("history.empty.weight", default: "No weight samples in this range."),
            seriesInk: ink
        ) {
            Chart {
                RuleMark(y: .value("Target", targetKg))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    .foregroundStyle(ink.opacity(0.55))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Text(
                            "\(AppLanguageStore.text("history.target", default: "Target")) \(String(format: "%.1f", UnitFormat.mass(fromKg: targetKg, system: session.preferredUnits)))"
                        )
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.78), in: Capsule())
                            .fixedSize()
                    }

                // Area first: yStart/yEnd to the plot floor (never fill toward 0 kg).
                // Skip AreaMark for a single point — zero-width fill can yield non-finite frames.
                if samples.count >= 2 {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("Date", sample.date),
                            yStart: .value("Floor", floorY),
                            yEnd: .value("Weight", sample.value),
                            series: .value("Series", "Fill")
                        )
                        .interpolationMethod(lineInterpolation)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [mid.opacity(0.42), mid.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value),
                        series: .value("Series", "Health")
                    )
                    .interpolationMethod(lineInterpolation)
                    .foregroundStyle(ink.opacity(0.92))
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                ForEach(samples) { sample in
                    PointMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value)
                    )
                    .symbolSize(selected?.id == sample.id ? 72 : 28)
                    .foregroundStyle(ink.opacity(0.85))
                }

                // Animated projection line; X domain grows with `projectionReveal`.
                if showTrend, let scientific {
                    let tempered = HealthChartMath.revealedProjectionPath(
                        scientific.temperedPath,
                        progress: projectionReveal
                    )
                    if tempered.count >= 2 {
                        ForEach(Array(tempered.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Weight", point.value),
                                series: .value("Series", "Projected")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(ink.opacity(0.82))
                            .interpolationMethod(.linear)
                        }
                    }

                    if projectionReveal > 0.96, let crossing = scientific.crossing {
                        projectedCrossingMark(
                            crossing: crossing,
                            xDomain: xDomain,
                            ink: ink,
                            formatMass: true
                        )
                    }

                    let observed = HealthChartMath.revealedProjectionPath(
                        scientific.observedPath,
                        progress: min(projectionReveal * 1.4, 1)
                    )
                    if observed.count >= 2 {
                        ForEach(Array(observed.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Weight", point.value),
                                series: .value("Series", "Observed")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
                            .foregroundStyle(ink.opacity(0.35))
                            .interpolationMethod(.linear)
                        }
                    }
                } else if showTrend, let projection {
                    let path = HealthChartMath.revealedProjectionPath(
                        projection.path,
                        progress: projectionReveal
                    )
                    if path.count >= 2 {
                        ForEach(Array(path.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Weight", point.value),
                                series: .value("Series", "Trend")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(ink.opacity(0.7))
                            .interpolationMethod(.linear)
                        }
                    }

                    if projectionReveal > 0.96, let crossing = projection.crossing {
                        projectedCrossingMark(
                            crossing: crossing,
                            xDomain: xDomain,
                            ink: ink,
                            formatMass: true
                        )
                    }
                }

                if let selectedDate {
                    RuleMark(x: .value("Selected", selectedDate))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(ink.opacity(0.35))
                }

                if let selected {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Weight", selected.value)
                    )
                    .symbolSize(90)
                    .foregroundStyle(ink)
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(UnitFormat.massString(selected.value, system: session.preferredUnits, fractionDigits: 1))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.88), in: Capsule())
                            .fixedSize()
                    }
                }

                if let extrema, selected == nil {
                    extremaMarks(extrema: extrema, title: "Weight", formatValue: { String(format: "%.1f", $0) }, ink: ink)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $selectedDate)
            .chartTapXSelection {
                weightYFloorMode.rotate()
                fatYFloorMode = weightYFloorMode
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .historyChartAxes(
                range: range,
                xDomain: xDomain,
                visibleLength: nil,
                accent: ink
            )
        }
    }

    private var bodyFatChartCard: some View {
        let samples = HealthChartMath.chartSeries(session.historyBodyFatPercents)
        let extrema = HealthChartMath.extrema(in: samples)
        let xDomain = historyXDomain(
            projection: showTrend ? weightProjection : nil,
            scientific: showTrend ? scientificProjection : nil
        )
        let visibleValues = HealthChartMath.valuesInVisibleXWindow(
            samples: samples,
            visibleStart: xDomain.lowerBound,
            visibleLength: nil,
            xDomain: xDomain
        )
        let domain = HealthChartMath.bodyFatDomain(
            values: visibleValues.isEmpty ? samples.map(\.value) : visibleValues,
            idealPercent: session.profile.idealBodyFatPercent,
            floorMode: fatYFloorMode
        )
        let selected = selectedDate.flatMap {
            HealthChartMath.nearestSample(in: samples, to: $0)
        }
        let floorY = domain.lowerBound
        let lineInterpolation: InterpolationMethod = samples.count >= 2 ? .monotone : .linear
        let ink = chartInk
        let mid = chartMid

        return metricScaffold(
            title: AppLanguageStore.text("live.body_fat", default: "Body fat"),
            unit: "%",
            samples: samples,
            extrema: extrema,
            formatValue: { String(format: "%.1f", $0) },
            emptyCopy: AppLanguageStore.text("history.empty.body_fat", default: "No body fat samples in this range."),
            seriesInk: ink
        ) {
            Chart {
                if let ideal = session.profile.idealBodyFatPercent {
                    RuleMark(y: .value("Ideal", ideal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(ink.opacity(0.45))
                        .annotation(position: .top, alignment: .leading, spacing: 4) {
                            Text(AppLanguageStore.text("history.target", default: "Target"))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(0.65))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.78), in: Capsule())
                                .fixedSize()
                        }
                }

                if samples.count >= 2 {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("Date", sample.date),
                            yStart: .value("Floor", floorY),
                            yEnd: .value("Body fat", sample.value),
                            series: .value("Series", "Fill")
                        )
                        .interpolationMethod(lineInterpolation)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [mid.opacity(0.42), mid.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Body fat", sample.value),
                        series: .value("Series", "Health")
                    )
                    .interpolationMethod(lineInterpolation)
                    .foregroundStyle(ink.opacity(0.92))
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                ForEach(samples) { sample in
                    PointMark(
                        x: .value("Date", sample.date),
                        y: .value("Body fat", sample.value)
                    )
                    .symbolSize(selected?.id == sample.id ? 72 : 28)
                    .foregroundStyle(ink.opacity(0.85))
                }

                if let selectedDate {
                    RuleMark(x: .value("Selected", selectedDate))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(ink.opacity(0.35))
                }

                if let selected {
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Body fat", selected.value)
                    )
                    .symbolSize(90)
                    .foregroundStyle(ink)
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(String(format: "%.1f%%", selected.value))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.88), in: Capsule())
                            .fixedSize()
                    }
                }

                if let extrema, selected == nil {
                    extremaMarks(extrema: extrema, title: "Body fat", formatValue: { String(format: "%.1f", $0) }, ink: ink)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $selectedDate)
            .chartTapXSelection {
                fatYFloorMode.rotate()
                weightYFloorMode = fatYFloorMode
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .historyChartAxes(
                range: range,
                xDomain: xDomain,
                visibleLength: nil,
                accent: ink
            )
        }
    }

    private func metricScaffold<Content: View>(
        title: String,
        unit: String,
        samples: [HealthMetricSample],
        extrema: (highest: HealthMetricSample, lowest: HealthMetricSample)?,
        formatValue: @escaping (Double) -> String,
        emptyCopy: String,
        seriesInk: Color,
        @ViewBuilder chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(seriesInk.opacity(0.78))
                Text(unit)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(seriesInk.opacity(0.55))
                Spacer(minLength: 8)
                if let extrema {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("H \(formatValue(extrema.highest.value)) · L \(formatValue(extrema.lowest.value))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(seriesInk.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let rate = HealthChartMath.ratePerWeek(samples: samples) {
                            Text("\(UnitFormat.massDeltaString(rate, system: session.preferredUnits, fractionDigits: 2)) / wk")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(seriesInk.opacity(0.55))
                        }
                    }
                }
            }

            if samples.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(seriesInk.opacity(0.45))
                    Text(emptyCopy)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(seriesInk.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 28)
            } else {
                // Chart chrome (axes/legend/scroll) must stay on the Chart itself.
                // Do not clip the Chart view — annotations (Projected / Target) live in the
                // margins and were getting trimmed by `.clipped()` / panel clipShape.
                chart()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleGlassPanel(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(title: title, unit: unit, samples: samples, extrema: extrema))
    }

    @ChartContentBuilder
    private func projectedCrossingMark(
        crossing: HealthMetricSample,
        xDomain: ClosedRange<Date>,
        ink: Color,
        formatMass: Bool
    ) -> some ChartContent {
        let opensLeading = HealthChartMath.annotationOpensLeading(at: crossing.date, in: xDomain)
        PointMark(
            x: .value("Date", crossing.date),
            y: .value("Weight", crossing.value)
        )
        .symbolSize(64)
        .foregroundStyle(ink)
        .annotation(
            position: .top,
            alignment: opensLeading ? .trailing : .leading,
            spacing: 6,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            VStack(alignment: opensLeading ? .trailing : .leading, spacing: 1) {
                Text(AppLanguageStore.text("history.projected", default: "Projected"))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                Text(crossing.date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text(
                    formatMass
                        ? UnitFormat.massString(crossing.value, system: session.preferredUnits, fractionDigits: 1)
                        : String(format: "%.1f%%", crossing.value)
                )
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .fixedSize()
        }
    }

    @ChartContentBuilder
    private func extremaMarks(
        extrema: (highest: HealthMetricSample, lowest: HealthMetricSample),
        title: String,
        formatValue: @escaping (Double) -> String,
        ink: Color
    ) -> some ChartContent {
        PointMark(
            x: .value("Date", extrema.highest.date),
            y: .value(title, extrema.highest.value)
        )
        .symbolSize(56)
        .foregroundStyle(ink)
        .annotation(
            position: .top,
            spacing: 4,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            Text("H \(formatValue(extrema.highest.value))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.7), in: Capsule())
                .fixedSize()
        }

        PointMark(
            x: .value("Date", extrema.lowest.date),
            y: .value(title, extrema.lowest.value)
        )
        .symbolSize(56)
        .foregroundStyle(ink)
        .annotation(
            position: .bottom,
            spacing: 4,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            Text("L \(formatValue(extrema.lowest.value))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.7), in: Capsule())
                .fixedSize()
        }
    }

    private func historyXDomain(
        projection: WeightTrendProjection?,
        scientific: ScientificWeightProjection?
    ) -> ClosedRange<Date> {
        let projectionDates = showTrend ? (projection?.path.map(\.date) ?? []) : []
        let scientificDates = showTrend
            ? ((scientific?.temperedPath.map(\.date) ?? []) + (scientific?.observedPath.map(\.date) ?? []))
            : []
        return HealthChartMath.historyXDomain(
            range: range,
            extraDates: projectionDates + scientificDates,
            revealProgress: showTrend ? projectionReveal : 0
        )
    }

    private func trendCaptionScientific(_ projection: ScientificWeightProjection) -> String {
        if let crossing = projection.crossing {
            let day = crossing.date.formatted(.dateTime.month(.abbreviated).day())
            let mass = UnitFormat.massString(crossing.value, system: session.preferredUnits, fractionDigits: 1)
            return "Projected → \(mass) · \(day)"
        }
        return "Projected (safe pace)"
    }

    private func trendCaption(_ projection: WeightTrendProjection) -> String {
        if let crossing = projection.crossing {
            let day = crossing.date.formatted(.dateTime.month(.abbreviated).day())
            let mass = UnitFormat.massString(crossing.value, system: session.preferredUnits, fractionDigits: 1)
            return "→ \(mass) · \(day)"
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

    private func animateProjectionReveal(_ isOn: Bool) {
        if isOn {
            projectionReveal = 0
            withAnimation(.easeOut(duration: 1.15)) {
                projectionReveal = 1
            }
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                projectionReveal = 0
            }
        }
    }
}

private extension View {
    /// Axes + legend applied directly on a Chart (before any scroll ConditionalContent).
    func historyChartAxes(
        range: HealthHistoryRange,
        xDomain: ClosedRange<Date>,
        visibleLength: TimeInterval?,
        accent: Color
    ) -> some View {
        // Approximate plot width from the foreground window scene (not UIScreen.main —
        // deprecated on iOS 26). Charts axis layout is not GeometryReader-friendly.
        let plotWidth = max(Double(Self.foregroundScreenWidth) - 112, 200)
        let marks = HealthChartMath.xAxisMarks(
            range: range,
            domain: xDomain,
            visibleLength: visibleLength,
            plotWidth: plotWidth
        )
        let tickDates = marks.map(\.date)
        return self
            // Force Charts to rebuild axis marks when the period picker changes.
            .id("history-x-\(range.rawValue)-\(tickDates.count)")
            .chartPlotStyle { plotArea in
                // Clip series only — annotations render above and must stay readable.
                plotArea.clipped()
            }
            .chartXAxis {
                AxisMarks(values: tickDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(accent.opacity(0.12))
                    AxisTick(length: 5, stroke: StrokeStyle(lineWidth: 1.2))
                        .foregroundStyle(accent.opacity(0.4))
                    // Named anchors only: custom UnitPoint crashes Charts layout noise on iOS 26+.
                    // Format live from `range` so labels always match the selected period
                    // (lookup against tick dates can miss after Charts date snapping).
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(HealthChartMath.formatXAxisLabel(date, range: range))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.top, 5)
                                .padding(.horizontal, 2)
                                .fixedSize(horizontal: true, vertical: false)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(accent.opacity(0.12))
                    AxisValueLabel(anchor: .trailing)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(accent.opacity(0.55))
                }
            }
            .chartLegend(.hidden)
    }

    /// Active window-scene screen width (iOS 26+ prefers this over `UIScreen.main`).
    static var foregroundScreenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.screen.bounds.width ?? 390
    }

    /// Tap/select activates the comment point immediately (default chartXSelection waits on long press).
    /// Taps on the leading Y-axis strip (~44pt) rotate the Y floor (target ↔ visible min).
    /// Taps on the plot **or** X-axis label band select the date under the finger.
    func chartTapXSelection(onYAxisTap: (() -> Void)? = nil) -> some View {
        chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { value in
                    if let onYAxisTap, value.location.x < 44 {
                        onYAxisTap()
                        return
                    }
                    proxy.selectXValue(at: value.location.x)
                }
        }
    }
}

#Preview {
    WeighInResultsView()
        .environmentObject(ScaleSessionViewModel())
}
