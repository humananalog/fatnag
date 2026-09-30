import Foundation

/// Time window for post-save Health history charts.
///
/// Segment order is fixed for the UI picker (left → right):
/// Last week, Last 2 weeks (default), Last month, Last 3 months, Last year.
enum HealthHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case lastWeek
    case lastTwoWeeks
    case lastMonth
    case lastThreeMonths
    case lastYear

    var id: String { rawValue }

    /// Default selection after a successful Health confirm.
    static let `default`: HealthHistoryRange = .lastTwoWeeks

    var title: String {
        switch self {
        case .lastWeek: return "1W"
        case .lastTwoWeeks: return "2W"
        case .lastMonth: return "1M"
        case .lastThreeMonths: return "3M"
        case .lastYear: return "1Y"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .lastWeek: return "Last week"
        case .lastTwoWeeks: return "Last 2 weeks"
        case .lastMonth: return "Last month"
        case .lastThreeMonths: return "Last 3 months"
        case .lastYear: return "Last year"
        }
    }

    /// Horizontal pan for longer ranges (iOS Charts scroll APIs).
    var prefersHorizontalScroll: Bool {
        switch self {
        case .lastThreeMonths, .lastYear: return true
        default: return false
        }
    }

    /// Visible X window length when scroll is enabled (seconds).
    var visibleDomainLength: TimeInterval {
        switch self {
        case .lastWeek: return 7 * 86_400
        case .lastTwoWeeks: return 14 * 86_400
        case .lastMonth: return 31 * 86_400
        case .lastThreeMonths: return 45 * 86_400
        case .lastYear: return 90 * 86_400
        }
    }

    /// Inclusive lookback from `now` (calendar days / months / year).
    func startDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        case .lastTwoWeeks:
            return calendar.date(byAdding: .day, value: -14, to: now) ?? now.addingTimeInterval(-14 * 86_400)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        case .lastThreeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now.addingTimeInterval(-90 * 86_400)
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
        }
    }
}

/// One Health quantity sample used by the results charts.
struct HealthMetricSample: Equatable, Identifiable, Sendable {
    let id: UUID
    let value: Double
    let date: Date

    init(id: UUID = UUID(), value: Double, date: Date) {
        self.id = id
        self.value = value
        self.date = date
    }
}

/// Forward weight projection toward ideal (Trend mode).
struct WeightTrendProjection: Equatable, Sendable {
    /// Health samples from the last 2 weeks that drove the fit.
    let windowSamples: [HealthMetricSample]
    /// kg per day (negative = losing).
    let slopeKgPerDay: Double
    /// Polyline from last observed sample through the crossing (or horizon).
    let path: [HealthMetricSample]
    /// Where the projected line meets ideal weight (date + ideal kg).
    let crossing: HealthMetricSample?
    /// True when the fit is moving toward ideal and crosses within the horizon.
    var reachesTarget: Bool { crossing != nil }
}

/// Medically tempered projection toward the user's target weight.
///
/// Combines OLS on recent Health mass samples with a capped safe rate
/// (about 0.5–1% body weight per week, max 1 kg/week loss) and soft
/// confidence from optional fitness digests (resting HR, steps, sleep).
struct ScientificWeightProjection: Equatable, Sendable {
    let windowSamples: [HealthMetricSample]
    /// Raw OLS slope from History (kg/day).
    let observedSlopeKgPerDay: Double
    /// Slope used for the tempered path to target (kg/day).
    let temperedSlopeKgPerDay: Double
    /// Short forward stub of the *observed* rate (may miss the target).
    let observedPath: [HealthMetricSample]
    /// Path toward target at the medically tempered rate.
    let temperedPath: [HealthMetricSample]
    let crossing: HealthMetricSample?
    /// 0...1 qualitative confidence from sample count + fitness signals.
    let confidence: Double
    let methodSummary: String
    let notes: [String]
}

/// Pure helpers for chart domain, extrema labels, and Trend projection.
enum HealthChartMath {
    /// Sort ascending and collapse near-duplicate timestamps so AreaMark / LineMark
    /// never scribble (identical X values + Catmull-Rom = classic "weird lines" bug).
    static func chartSeries(
        _ samples: [HealthMetricSample],
        mergeWithinSeconds: TimeInterval = 2
    ) -> [HealthMetricSample] {
        let ordered = samples.sorted { $0.date < $1.date }
        guard !ordered.isEmpty else { return [] }
        var out: [HealthMetricSample] = []
        out.reserveCapacity(ordered.count)
        for sample in ordered {
            if let last = out.last, abs(last.date.timeIntervalSince(sample.date)) < mergeWithinSeconds {
                out[out.count - 1] = sample
            } else {
                out.append(sample)
            }
        }
        return out
    }

    /// Y-axis floor for History charts. Tap the Y-axis to rotate.
    /// - `target`: floor at the Target/Ideal line (still expands down to include any data below it).
    /// - `visibleData`: floor at the minimum sample in the currently visible X window.
    enum ChartYFloorMode: String, CaseIterable, Sendable {
        case target
        case visibleData

        mutating func rotate() {
            self = self == .target ? .visibleData : .target
        }
    }

    /// Samples whose dates fall in the visible scroll window (or the full X domain).
    static func valuesInVisibleXWindow(
        samples: [HealthMetricSample],
        visibleStart: Date,
        visibleLength: TimeInterval?,
        xDomain: ClosedRange<Date>
    ) -> [Double] {
        let length: TimeInterval
        if let visibleLength, visibleLength.isFinite, visibleLength > 0 {
            length = visibleLength
        } else {
            length = max(xDomain.upperBound.timeIntervalSince(xDomain.lowerBound), 1)
        }
        let end = visibleStart.addingTimeInterval(length)
        let start = min(visibleStart, end)
        let stop = max(visibleStart, end)
        let inWindow = samples.compactMap { sample -> Double? in
            guard sample.date >= start, sample.date <= stop else { return nil }
            return finiteOrNil(sample.value)
        }
        if !inWindow.isEmpty { return inWindow }
        return samples.compactMap { finiteOrNil($0.value) }
    }

    /// Y-axis / domain for the weight chart.
    ///
    /// Ideal weight from Settings draws as the Ideal reference line. Upper bound
    /// is `max(dataMax, ideal, projectionMax) + padding`. Floor follows `floorMode`.
    static func weightDomain(
        values: [Double],
        idealKg: Double,
        paddingFraction: Double = 0.08,
        extraValues: [Double] = [],
        floorMode: ChartYFloorMode = .target
    ) -> ClosedRange<Double> {
        let ideal = max(finiteOrNil(idealKg) ?? 1, 1)
        let combined = (values + extraValues).compactMap(finiteOrNil)
        guard let dataMin = combined.min(), let dataMax = combined.max() else {
            return sanitizeDomain(ideal...(ideal + 5))
        }
        let floor: Double
        switch floorMode {
        case .target:
            // Target line as minimum; never clip real Health points below the goal.
            floor = min(dataMin, ideal)
        case .visibleData:
            // Zoom to visible sample min (target may sit at/below the plot floor).
            floor = dataMin
        }
        let top = max(dataMax, ideal)
        let span = max(top - floor, 0.5)
        let pad = max(span * paddingFraction, 0.15)
        return sanitizeDomain((floor - pad * 0.25)...(top + pad))
    }

    /// Y-axis for body fat %. Floor follows `floorMode` when ideal is set.
    static func bodyFatDomain(
        values: [Double],
        idealPercent: Double?,
        paddingFraction: Double = 0.12,
        floorMode: ChartYFloorMode = .target
    ) -> ClosedRange<Double> {
        let finiteValues = values.compactMap(finiteOrNil)
        guard let dataMin = finiteValues.min(), let dataMax = finiteValues.max() else {
            if let ideal = idealPercent.flatMap(finiteOrNil) {
                let floor = max(ideal, 0)
                return sanitizeDomain(floor...(floor + 8))
            }
            return 10...30
        }
        if let ideal = idealPercent.flatMap(finiteOrNil) {
            let floor: Double
            switch floorMode {
            case .target:
                floor = max(min(ideal, dataMin), 0)
            case .visibleData:
                floor = max(dataMin, 0)
            }
            let top = max(dataMax, ideal)
            let span = max(top - floor, 1)
            let pad = max(span * paddingFraction, 0.4)
            return sanitizeDomain(floor...(top + pad))
        }
        let span = max(dataMax - dataMin, 1)
        let pad = max(span * paddingFraction, 0.5)
        let low = max(dataMin - pad, 0)
        let high = min(dataMax + pad, 75)
        return sanitizeDomain(low...max(high, low + 1))
    }

    /// X-axis for History charts.
    ///
    /// Always spans the selected filter window (`range.start`…`now`), not just the
    /// sample extents. Sparse Health data over 3M/1Y used to shrink the plot domain
    /// below `chartXVisibleDomain`, which made Charts emit
    /// `Invalid frame dimension (negative or non-finite)`. Projection dates past
    /// `now` extend the upper bound so Trend lines stay in-frame.
    static func historyXDomain(
        range: HealthHistoryRange,
        extraDates: [Date] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let start = range.startDate(relativeTo: now, calendar: calendar)
        var end = now
        if let furthest = extraDates.max(), furthest > end {
            end = furthest
        }
        var span = end.timeIntervalSince(start)
        if !span.isFinite || span <= 0 {
            // Single-instant / inverted fallback: one calendar day centered on now.
            return now.addingTimeInterval(-43_200)...now.addingTimeInterval(43_200)
        }
        // Charts needs a strictly positive domain; keep at least one day.
        if span < 86_400 {
            end = start.addingTimeInterval(86_400)
            span = 86_400
        }
        let pad = max(span * 0.02, 3_600)
        return start...end.addingTimeInterval(pad)
    }

    /// Visible scroll window for 3M/1Y, or `nil` when scroll must stay off.
    ///
    /// `chartXVisibleDomain(length:)` must be **strictly shorter** than the plot
    /// X domain. Returning `nil` disables scroll instead of feeding Charts a
    /// length that produces negative leftover geometry.
    static func scrollVisibleDomainLength(
        for range: HealthHistoryRange,
        xDomain: ClosedRange<Date>
    ) -> TimeInterval? {
        guard range.prefersHorizontalScroll else { return nil }
        let span = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard span.isFinite, span > 0 else { return nil }
        let wanted = range.visibleDomainLength
        guard wanted.isFinite, wanted > 0 else { return nil }
        // Require headroom so layout math stays positive after axis/chrome insets.
        // Charts emits Invalid frame dimension when leftover plot width collapses.
        guard span > wanted * 1.20 else { return nil }
        let capped = min(wanted, span * 0.82)
        guard capped.isFinite, capped > 0, capped < span - 86_400 * 0.12 else { return nil }
        return capped
    }

    /// Leading edge of the visible window so the **most recent** data is on screen.
    /// Default Charts scroll starts at domain.lowerBound, which looks empty on sparse 3M/1Y.
    static func scrollLeadingDate(
        xDomain: ClosedRange<Date>,
        visibleLength: TimeInterval
    ) -> Date {
        guard visibleLength.isFinite, visibleLength > 0 else { return xDomain.lowerBound }
        let candidate = xDomain.upperBound.addingTimeInterval(-visibleLength)
        return max(candidate, xDomain.lowerBound)
    }

    /// Collapse non-finite / inverted Y domains into a safe positive span.
    static func sanitizeDomain(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        var lo = range.lowerBound
        var hi = range.upperBound
        if !lo.isFinite { lo = 0 }
        if !hi.isFinite { hi = lo + 1 }
        if hi <= lo { hi = lo + max(abs(lo) * 0.05, 1) }
        return lo...hi
    }

    private static func finiteOrNil(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    static func extrema(in samples: [HealthMetricSample]) -> (highest: HealthMetricSample, lowest: HealthMetricSample)? {
        guard let first = samples.first else { return nil }
        var highest = first
        var lowest = first
        for sample in samples.dropFirst() {
            if sample.value > highest.value { highest = sample }
            if sample.value < lowest.value { lowest = sample }
        }
        return (highest, lowest)
    }

    /// Nearest Health sample to a chart selection date (for tap callouts).
    static func nearestSample(in samples: [HealthMetricSample], to date: Date) -> HealthMetricSample? {
        guard !samples.isEmpty else { return nil }
        return samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// OLS slope converted to units per week (kg/wk or %/wk). Nil if under-sampled.
    static func ratePerWeek(samples: [HealthMetricSample]) -> Double? {
        guard let fit = ordinaryLeastSquares(samples: samples) else { return nil }
        return fit.slopeKgPerSecond * 86_400 * 7
    }

    /// Simple least-squares line through (time, value) over the given samples.
    /// Returns endpoints spanning the sample window (historical fit only).
    static func linearTrendEndpoints(
        samples: [HealthMetricSample]
    ) -> (start: HealthMetricSample, end: HealthMetricSample)? {
        guard let fit = ordinaryLeastSquares(samples: samples) else { return nil }
        let ordered = samples.sorted { $0.date < $1.date }
        let yStart = fit.value(at: ordered.first!.date)
        let yEnd = fit.value(at: ordered.last!.date)
        return (
            HealthMetricSample(id: UUID(), value: yStart, date: ordered.first!.date),
            HealthMetricSample(id: UUID(), value: yEnd, date: ordered.last!.date)
        )
    }

    /// Trend projection toward ideal weight.
    ///
    /// **Method (documented):** ordinary least-squares linear regression on the
    /// last **14 calendar days** of Apple Health `bodyMass` samples (sparse daily
    /// weighs). LOESS is unnecessary for ~2-14 points; a centered moving average
    /// would lag and understate slope on sparse data. OLS on the recent window is
    /// the practical clinical shorthand for "recent rate of change" and stays
    /// stable with uneven weigh-in days.
    ///
    /// The projected ray starts at the last observed Health sample and extends
    /// forward until it crosses `idealKg` (or `maxHorizonDays` if the slope does
    /// not move toward ideal). Crossing label uses ideal kg at the crossing date.
    static func projectWeightToIdeal(
        windowSamples: [HealthMetricSample],
        idealKg: Double,
        now: Date = Date(),
        maxHorizonDays: Int = 730,
        calendar: Calendar = .current
    ) -> WeightTrendProjection? {
        let ordered = windowSamples.sorted { $0.date < $1.date }
        guard ordered.count >= 2, let fit = ordinaryLeastSquares(samples: ordered) else {
            return nil
        }

        let ideal = max(idealKg, 1)
        let last = ordered.last!
        let slopePerDay = fit.slopeKgPerSecond * 86_400
        let startDate = max(last.date, now)
        let startValue = fit.value(at: startDate)

        var path: [HealthMetricSample] = [
            HealthMetricSample(id: last.id, value: last.value, date: last.date)
        ]
        if abs(startDate.timeIntervalSince(last.date)) > 1 {
            path.append(HealthMetricSample(value: startValue, date: startDate))
        }

        let movingTowardIdeal: Bool = {
            if abs(startValue - ideal) < 0.05 { return true }
            if startValue > ideal { return slopePerDay < -0.001 }
            return slopePerDay > 0.001
        }()

        guard movingTowardIdeal else {
            // Still return a short dashed stub so the control feedback is visible.
            let stubEnd = calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate.addingTimeInterval(7 * 86_400)
            path.append(HealthMetricSample(value: fit.value(at: stubEnd), date: stubEnd))
            return WeightTrendProjection(
                windowSamples: ordered,
                slopeKgPerDay: slopePerDay,
                path: path,
                crossing: nil
            )
        }

        if abs(startValue - ideal) < 0.05 {
            let crossing = HealthMetricSample(value: ideal, date: startDate)
            path.append(crossing)
            return WeightTrendProjection(
                windowSamples: ordered,
                slopeKgPerDay: slopePerDay,
                path: path,
                crossing: crossing
            )
        }

        // Solve ideal = intercept + slope * (t - t0) → t = t0 + (ideal - intercept) / slope
        guard abs(fit.slopeKgPerSecond) > 1e-15 else {
            let stubEnd = calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate.addingTimeInterval(7 * 86_400)
            path.append(HealthMetricSample(value: fit.value(at: stubEnd), date: stubEnd))
            return WeightTrendProjection(
                windowSamples: ordered,
                slopeKgPerDay: slopePerDay,
                path: path,
                crossing: nil
            )
        }
        let deltaSeconds = (ideal - fit.interceptKg) / fit.slopeKgPerSecond
        let crossingDate = Date(timeIntervalSinceReferenceDate: fit.t0.timeIntervalSinceReferenceDate + deltaSeconds)
        let horizon = calendar.date(byAdding: .day, value: maxHorizonDays, to: startDate)
            ?? startDate.addingTimeInterval(TimeInterval(maxHorizonDays) * 86_400)

        if crossingDate > startDate, crossingDate <= horizon {
            // Dense-enough polyline for a smooth Chart animation (daily steps, capped).
            let totalDays = max(Int(ceil(crossingDate.timeIntervalSince(startDate) / 86_400)), 1)
            let stepDays = max(totalDays / 24, 1)
            var cursor = startDate
            while cursor < crossingDate {
                cursor = calendar.date(byAdding: .day, value: stepDays, to: cursor)
                    ?? cursor.addingTimeInterval(TimeInterval(stepDays) * 86_400)
                if cursor >= crossingDate { break }
                path.append(HealthMetricSample(value: fit.value(at: cursor), date: cursor))
            }
            let crossing = HealthMetricSample(value: ideal, date: crossingDate)
            path.append(crossing)
            return WeightTrendProjection(
                windowSamples: ordered,
                slopeKgPerDay: slopePerDay,
                path: path,
                crossing: crossing
            )
        }

        let endValue = fit.value(at: horizon)
        path.append(HealthMetricSample(value: endValue, date: horizon))
        return WeightTrendProjection(
            windowSamples: ordered,
            slopeKgPerDay: slopePerDay,
            path: path,
            crossing: nil
        )
    }

    /// Scientific, medically tempered projection to `idealKg`.
    ///
    /// **Algorithm:**
    /// 1. Adaptive window: prefer last 42 days if ≥4 samples, else last 14, else all (≥2).
    /// 2. OLS slope on that window (observed rate).
    /// 3. Safe rate toward target: ≤ `TargetFeasibility.maxSafeLoss/GainKgPerWeek`.
    /// 4. If observed rate aims at target and is within the safe band, use it; else temper.
    /// 5. Soft modulators from `FitnessDigest` (elevated resting HR / very low steps
    ///    reduce confidence and slightly slow the tempered rate).
    /// 6. Build a polyline to the target (or horizon) at the tempered slope.
    static func scientificProjectWeight(
        samples: [HealthMetricSample],
        idealKg: Double,
        currentKg: Double?,
        heightCm: Double,
        sex: UserBodyProfile.Sex,
        digest: FitnessDigest? = nil,
        now: Date = Date(),
        maxHorizonDays: Int = 730,
        calendar: Calendar = .current
    ) -> ScientificWeightProjection? {
        let series = chartSeries(samples)
        let window = adaptiveProjectionWindow(series, now: now, calendar: calendar)
        guard window.count >= 2, let fit = ordinaryLeastSquares(samples: window) else {
            return nil
        }

        let ideal = max(idealKg, 1)
        let last = window.last!
        let startKg = currentKg ?? last.value
        let observedSlopePerDay = fit.slopeKgPerSecond * 86_400
        let startDate = max(last.date, now)

        var notes: [String] = []
        var confidence = min(1.0, 0.35 + 0.08 * Double(window.count))
        var rateScale = 1.0

        if let digest {
            if let rhr = digest.restingHeartRateBpm, rhr >= 85 {
                confidence *= 0.85
                rateScale *= 0.9
                notes.append("Resting HR elevated; tempered pace slowed slightly.")
            }
            if let steps = digest.stepsToday, steps < 3_000 {
                confidence *= 0.9
                rateScale *= 0.92
                notes.append("Low step count today; sustainable deficit may be harder.")
            }
            if let hours = digest.sleepHoursLastNight, hours < 5.5 {
                confidence *= 0.88
                rateScale *= 0.9
                notes.append("Short sleep; recovery-limited pace.")
            }
            if let hrv = digest.hrvSDNNMs, let median = digest.hrvMedian7dMs, median > 0, hrv / median < 0.7 {
                confidence *= 0.9
                rateScale *= 0.92
                notes.append("HRV SDNN below recent median; tempered pace slowed slightly.")
            }
            if let recovery = digest.recovery, recovery.band == .red {
                confidence *= 0.85
                rateScale *= 0.88
                notes.append("Recovery heuristic in red band; tempered pace slowed.")
            }
        }

        let towardLower = startKg > ideal + 0.05
        let towardHigher = startKg < ideal - 0.05
        let safeLossPerDay = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: startKg) / 7.0 * rateScale
        let safeGainPerDay = TargetFeasibility.maxSafeGainKgPerWeek(currentKg: startKg) / 7.0 * rateScale

        let temperedSlopePerDay: Double = {
            if abs(startKg - ideal) < 0.05 { return 0 }
            if towardLower {
                // Need negative slope. Cap magnitude at safe loss.
                let desired = -safeLossPerDay
                if observedSlopePerDay < 0 {
                    // Observed already losing: use the gentler of observed vs safe (less aggressive).
                    return max(observedSlopePerDay, desired)
                }
                return desired
            }
            if towardHigher {
                let desired = safeGainPerDay
                if observedSlopePerDay > 0 {
                    return min(observedSlopePerDay, desired)
                }
                return desired
            }
            return 0
        }()

        if towardLower, observedSlopePerDay < -safeLossPerDay - 0.001 {
            notes.append(
                String(format: "Observed loss faster than ~%.1f kg/wk safe band; projection tempered.", safeLossPerDay * 7)
            )
        }
        if towardLower, observedSlopePerDay >= -0.0005 {
            notes.append("Recent trend is flat or up; projection uses a safe loss rate toward target.")
        }
        if towardHigher, observedSlopePerDay <= 0.0005 {
            notes.append("Recent trend is flat or down; projection uses a modest gain rate toward target.")
        }

        // Observed stub (7–21 days of raw OLS)
        var observedPath: [HealthMetricSample] = [
            HealthMetricSample(id: last.id, value: last.value, date: last.date)
        ]
        let obsEnd = calendar.date(byAdding: .day, value: 14, to: startDate)
            ?? startDate.addingTimeInterval(14 * 86_400)
        observedPath.append(HealthMetricSample(value: fit.value(at: startDate), date: startDate))
        observedPath.append(HealthMetricSample(value: fit.value(at: obsEnd), date: obsEnd))

        // Tempered path to target
        var temperedPath: [HealthMetricSample] = [
            HealthMetricSample(id: last.id, value: last.value, date: last.date)
        ]
        if abs(startDate.timeIntervalSince(last.date)) > 1 {
            temperedPath.append(HealthMetricSample(value: startKg, date: startDate))
        }

        var crossing: HealthMetricSample?
        if abs(startKg - ideal) < 0.05 {
            crossing = HealthMetricSample(value: ideal, date: startDate)
            temperedPath.append(crossing!)
        } else if abs(temperedSlopePerDay) > 1e-6 {
            let daysNeeded = (ideal - startKg) / temperedSlopePerDay
            let horizon = calendar.date(byAdding: .day, value: maxHorizonDays, to: startDate)
                ?? startDate.addingTimeInterval(TimeInterval(maxHorizonDays) * 86_400)
            if daysNeeded > 0 {
                let crossDate = startDate.addingTimeInterval(daysNeeded * 86_400)
                if crossDate <= horizon {
                    let totalDays = max(Int(ceil(daysNeeded)), 1)
                    let stepDays = max(totalDays / 24, 1)
                    var cursor = startDate
                    while cursor < crossDate {
                        cursor = calendar.date(byAdding: .day, value: stepDays, to: cursor)
                            ?? cursor.addingTimeInterval(TimeInterval(stepDays) * 86_400)
                        if cursor >= crossDate { break }
                        let y = startKg + temperedSlopePerDay * cursor.timeIntervalSince(startDate) / 86_400
                        temperedPath.append(HealthMetricSample(value: y, date: cursor))
                    }
                    crossing = HealthMetricSample(value: ideal, date: crossDate)
                    temperedPath.append(crossing!)
                } else {
                    let y = startKg + temperedSlopePerDay * horizon.timeIntervalSince(startDate) / 86_400
                    temperedPath.append(HealthMetricSample(value: y, date: horizon))
                    notes.append("Target beyond \(maxHorizonDays)-day horizon at a safe pace.")
                }
            }
        }

        let method = String(
            format: "OLS on %d Health weights (adaptive window) + safe rate ≤ %.2f kg/wk; confidence %.0f%%.",
            window.count,
            towardLower ? safeLossPerDay * 7 : safeGainPerDay * 7,
            confidence * 100
        )

        // Silence unused sex for now (reserved for future lean-mass-aware models).
        _ = sex
        _ = heightCm

        return ScientificWeightProjection(
            windowSamples: window,
            observedSlopeKgPerDay: observedSlopePerDay,
            temperedSlopeKgPerDay: temperedSlopePerDay,
            observedPath: observedPath,
            temperedPath: temperedPath,
            crossing: crossing,
            confidence: confidence,
            methodSummary: method,
            notes: notes
        )
    }

    /// Prefer 42-day window with enough points; fall back to 14 days; else all samples.
    static func adaptiveProjectionWindow(
        _ samples: [HealthMetricSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HealthMetricSample] {
        let ordered = chartSeries(samples)
        guard !ordered.isEmpty else { return [] }
        let day42 = calendar.date(byAdding: .day, value: -42, to: now) ?? now.addingTimeInterval(-42 * 86_400)
        let day14 = calendar.date(byAdding: .day, value: -14, to: now) ?? now.addingTimeInterval(-14 * 86_400)
        let w42 = ordered.filter { $0.date >= day42 }
        if w42.count >= 4 { return w42 }
        let w14 = ordered.filter { $0.date >= day14 }
        if w14.count >= 2 { return w14 }
        return ordered
    }

    static func filter(_ samples: [HealthMetricSample], range: HealthHistoryRange, now: Date = Date()) -> [HealthMetricSample] {
        let start = range.startDate(relativeTo: now)
        return samples
            .filter { $0.date >= start && $0.date <= now.addingTimeInterval(60) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - OLS

    fileprivate struct LinearFit {
        let t0: Date
        /// kg per second since `t0`.
        let slopeKgPerSecond: Double
        let interceptKg: Double

        func value(at date: Date) -> Double {
            let x = date.timeIntervalSinceReferenceDate - t0.timeIntervalSinceReferenceDate
            return interceptKg + slopeKgPerSecond * x
        }
    }

    fileprivate static func ordinaryLeastSquares(samples: [HealthMetricSample]) -> LinearFit? {
        guard samples.count >= 2 else { return nil }
        let ordered = samples.sorted { $0.date < $1.date }
        let t0 = ordered[0].date
        let xs = ordered.map { $0.date.timeIntervalSinceReferenceDate - t0.timeIntervalSinceReferenceDate }
        let ys = ordered.map(\.value)
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return LinearFit(t0: t0, slopeKgPerSecond: slope, interceptKg: intercept)
    }
}
