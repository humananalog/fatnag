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

    /// Y-axis / domain for the weight chart.
    ///
    /// Ideal weight from Settings draws as the Ideal reference line. The plot
    /// domain always includes **all Health samples** (`min(dataMin, ideal)` floor)
    /// so History never clips real HealthKit points below the goal. Upper bound
    /// is `max(dataMax, ideal, projectionMax) + padding`.
    static func weightDomain(
        values: [Double],
        idealKg: Double,
        paddingFraction: Double = 0.08,
        extraValues: [Double] = []
    ) -> ClosedRange<Double> {
        let ideal = max(idealKg, 1)
        let combined = values + extraValues
        guard let dataMin = combined.min(), let dataMax = combined.max() else {
            return ideal...(ideal + 5)
        }
        let floor = min(dataMin, ideal)
        let top = max(dataMax, ideal)
        let span = max(top - floor, 0.5)
        let pad = max(span * paddingFraction, 0.15)
        return (floor - pad * 0.25)...(top + pad)
    }

    /// Y-axis for body fat %. Prefer ideal as soft floor when set; always include data.
    static func bodyFatDomain(
        values: [Double],
        idealPercent: Double?,
        paddingFraction: Double = 0.12
    ) -> ClosedRange<Double> {
        guard let dataMin = values.min(), let dataMax = values.max() else {
            if let ideal = idealPercent {
                let floor = max(ideal, 0)
                return floor...(floor + 8)
            }
            return 10...30
        }
        if let ideal = idealPercent {
            let floor = max(min(ideal, dataMin), 0)
            let top = max(dataMax, ideal)
            let span = max(top - floor, 1)
            let pad = max(span * paddingFraction, 0.4)
            return floor...(top + pad)
        }
        let span = max(dataMax - dataMin, 1)
        let pad = max(span * paddingFraction, 0.5)
        let low = max(dataMin - pad, 0)
        let high = min(dataMax + pad, 75)
        return low...max(high, low + 1)
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
