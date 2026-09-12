import Charts
import SwiftUI

/// Post-confirm history: weight (kg) and body fat % from Apple Health.
///
/// Same visual language as the live sheet (materials, trend atmosphere, serif title).
/// Layout contract: content-first VStack; atmosphere is `.background` only so
/// oversized ellipses cannot widen the sheet and clip mid-word labels.
struct WeighInResultsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var range: HealthHistoryRange = .default
    @State private var animateCharts = false
    @State private var loadError: String?

    private let horizontalInset: CGFloat = 24
    private let panelInnerPad: CGFloat = 14

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            rangePicker
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
        .task(id: range) {
            await reload(for: range)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) {
                animateCharts = true
            }
        }
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
                Text("History")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(atmosphere.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Saved to Apple Health")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Label("Done", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(atmosphere.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityHidden(true)
                .onTapGesture { session.dismissResults() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }

    private var rangePicker: some View {
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
            animateCharts = false
            withAnimation(.easeOut(duration: 0.7)) {
                animateCharts = true
            }
        }
    }

    private var chartsColumn: some View {
        VStack(spacing: 12) {
            metricChartCard(
                title: "Weight",
                unit: "kg",
                samples: session.historyWeights,
                ideal: session.profile.idealWeightKg,
                idealLabel: "Ideal",
                domain: HealthChartMath.weightDomain(
                    values: session.historyWeights.map(\.value),
                    idealKg: session.profile.idealWeightKg
                ),
                formatValue: { String(format: "%.1f", $0) }
            )

            metricChartCard(
                title: "Body fat",
                unit: "%",
                samples: session.historyBodyFatPercents,
                ideal: session.profile.idealBodyFatPercent,
                idealLabel: "Ideal",
                domain: HealthChartMath.bodyFatDomain(
                    values: session.historyBodyFatPercents.map(\.value),
                    idealPercent: session.profile.idealBodyFatPercent
                ),
                formatValue: { String(format: "%.1f", $0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func metricChartCard(
        title: String,
        unit: String,
        samples: [HealthMetricSample],
        ideal: Double?,
        idealLabel: String,
        domain: ClosedRange<Double>,
        formatValue: @escaping (Double) -> String
    ) -> some View {
        let extrema = HealthChartMath.extrema(in: samples)
        let trend = HealthChartMath.linearTrendEndpoints(samples: samples)
        let plotted = animateCharts ? samples : []

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.78))
                Text(unit)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.55))
                Spacer(minLength: 8)
                if let extrema {
                    Text("H \(formatValue(extrema.highest.value)) · L \(formatValue(extrema.lowest.value))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(atmosphere.accent.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if samples.isEmpty {
                Text(title == "Weight" ? "No weight samples in this range." : "No body fat samples in this range.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Chart {
                    if let ideal {
                        RuleMark(y: .value("Ideal", ideal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(atmosphere.accent.opacity(0.45))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(idealLabel)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(atmosphere.accent.opacity(0.55))
                                    .padding(.trailing, 2)
                            }
                    }

                    if let trend {
                        ForEach([trend.start, trend.end]) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value(title, point.value),
                                series: .value("Series", "Trend")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                            .foregroundStyle(atmosphere.accent.opacity(0.4))
                            .interpolationMethod(.linear)
                        }
                    }

                    ForEach(plotted) { sample in
                        LineMark(
                            x: .value("Date", sample.date),
                            y: .value(title, sample.value),
                            series: .value("Series", "Data")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(atmosphere.accent.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                        AreaMark(
                            x: .value("Date", sample.date),
                            y: .value(title, sample.value)
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
                            y: .value(title, sample.value)
                        )
                        .symbolSize(28)
                        .foregroundStyle(atmosphere.accent.opacity(0.85))
                    }

                    if let extrema {
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
                }
                .chartYScale(domain: domain)
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
                .opacity(animateCharts ? 1 : 0.15)
                .animation(.easeOut(duration: 0.85), value: animateCharts)
                .animation(.easeOut(duration: 0.55), value: samples.count)
            }
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(title: title, unit: unit, samples: samples, extrema: extrema))
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

#Preview {
    WeighInResultsView()
        .environmentObject(ScaleSessionViewModel())
}
