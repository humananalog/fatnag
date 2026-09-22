import Foundation

/// On-device chart point comments (last 30 days). Never leave the phone except as compact Coach context.
struct ChartComment: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    /// Day the chart sample belongs to (start of day local).
    var sampleDay: Date
    var metric: ChartCommentMetric
    var text: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sampleDay: Date,
        metric: ChartCommentMetric,
        text: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sampleDay = sampleDay
        self.metric = metric
        self.text = String(text.prefix(256))
        self.updatedAt = updatedAt
    }
}

enum ChartCommentMetric: String, Codable, Sendable {
    case weight
    case bodyFat
}

enum ChartCommentStore {
    private static let key = "thescale.chartComments.v1"
    private static let retentionDays = 30
    static let maxLength = 256

    static func load() -> [ChartComment] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let comments = try? JSONDecoder().decode([ChartComment].self, from: data)
        else { return [] }
        return prune(comments)
    }

    static func save(_ comments: [ChartComment]) {
        let pruned = prune(comments)
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(sampleDay: Date, metric: ChartCommentMetric, text: String, now: Date = Date()) {
        let day = startOfDay(sampleDay)
        let cleaned = CoachCopySanitize.clean(String(text.prefix(maxLength)))
        var all = load()
        if cleaned.isEmpty {
            all.removeAll { startOfDay($0.sampleDay) == day && $0.metric == metric }
        } else if let idx = all.firstIndex(where: { startOfDay($0.sampleDay) == day && $0.metric == metric }) {
            all[idx].text = cleaned
            all[idx].updatedAt = now
        } else {
            all.append(ChartComment(sampleDay: day, metric: metric, text: cleaned, updatedAt: now))
        }
        save(all)
    }

    static func comment(on sampleDay: Date, metric: ChartCommentMetric) -> ChartComment? {
        let day = startOfDay(sampleDay)
        return load().first { startOfDay($0.sampleDay) == day && $0.metric == metric }
    }

    /// Compact block for weigh-in analysis / Grok (last 30 days only).
    static func analysisPayload(now: Date = Date(), calendar: Calendar = .current) -> String {
        let comments = load()
        guard !comments.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let lines = comments
            .sorted { $0.sampleDay > $1.sampleDay }
            .prefix(20)
            .map { "\(formatter.string(from: $0.sampleDay)) [\($0.metric.rawValue)]: \($0.text)" }
        return """
        Chart comments (on-device, last 30 days):
        \(lines.joined(separator: "\n"))
        """
    }

    private static func prune(_ comments: [ChartComment], now: Date = Date()) -> [ChartComment] {
        let cutoff = calendarStart(now).addingTimeInterval(-Double(retentionDays) * 86_400)
        return comments
            .filter { $0.sampleDay >= cutoff }
            .map {
                var c = $0
                c.text = String(c.text.prefix(maxLength))
                return c
            }
    }

    private static func startOfDay(_ date: Date) -> Date {
        calendarStart(date)
    }

    private static func calendarStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
