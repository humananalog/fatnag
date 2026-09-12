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

/// Pure helpers for chart domain, extrema labels, and a thin linear trend.
enum HealthChartMath {
    /// Y-axis / domain for the weight chart.
    ///
    /// **Choice (documented):** ideal weight from Settings is the **axis floor**
    /// (lower bound of the plot domain) and also draws as a clear ideal reference
    /// line. The top bound is `max(dataMax, ideal) + padding`. If any sample sits
    /// below ideal, the floor still stays at ideal so the chart never paints
    /// below the goal line (those points clamp visually against the floor edge
    /// via domain; labels still report true min/max from data).
    static func weightDomain(
        values: [Double],
        idealKg: Double,
        paddingFraction: Double = 0.08
    ) -> ClosedRange<Double> {
        let ideal = max(idealKg, 1)
        guard let dataMin = values.min(), let dataMax = values.max() else {
            return ideal...(ideal + 5)
        }
        let top = max(dataMax, ideal)
        let span = max(top - ideal, 0.5)
        let pad = max(span * paddingFraction, 0.15)
        return ideal...(top + pad)
    }

    /// Y-axis for body fat %. Prefer ideal as floor when set; else auto with pad.
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

    /// Simple least-squares line through (time, value). Returns two endpoints for plotting.
    static func linearTrendEndpoints(
        samples: [HealthMetricSample]
    ) -> (start: HealthMetricSample, end: HealthMetricSample)? {
        guard samples.count >= 2 else { return nil }
        let ordered = samples.sorted { $0.date < $1.date }
        let t0 = ordered[0].date.timeIntervalSinceReferenceDate
        let xs = ordered.map { $0.date.timeIntervalSinceReferenceDate - t0 }
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
        let yStart = intercept
        let yEnd = intercept + slope * (xs.last ?? 0)
        return (
            HealthMetricSample(id: UUID(), value: yStart, date: ordered.first!.date),
            HealthMetricSample(id: UUID(), value: yEnd, date: ordered.last!.date)
        )
    }

    static func filter(_ samples: [HealthMetricSample], range: HealthHistoryRange, now: Date = Date()) -> [HealthMetricSample] {
        let start = range.startDate(relativeTo: now)
        return samples
            .filter { $0.date >= start && $0.date <= now.addingTimeInterval(60) }
            .sorted { $0.date < $1.date }
    }
}
