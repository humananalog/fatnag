import Foundation

/// Local ISO-week identity for Monday card caching.
struct MondayWeekKey: Equatable, Hashable, Codable, Sendable {
    let weekOfYear: Int
    let yearForWeekOfYear: Int

    var storageKey: String { "\(yearForWeekOfYear)-W\(weekOfYear)" }

    static func current(now: Date = Date(), calendar: Calendar = .current) -> MondayWeekKey {
        let cal = MondayCardEngine.mondayBasedCalendar(from: calendar)
        let comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        return MondayWeekKey(
            weekOfYear: comps.weekOfYear ?? 1,
            yearForWeekOfYear: comps.yearForWeekOfYear ?? cal.component(.year, from: now)
        )
    }
}

/// Result of re-anchoring weekly progress to the local Monday week start.
struct WeekStartReconcile: Equatable, Sendable {
    var weekStartKg: Double?
    var weekStartDate: Date
    var didChange: Bool
    var reason: String
}

/// Deterministic last-week + Sunday-goal numbers. Live Keel fills voice / meals / diagnostic.
struct MondayWeekProgress: Equatable, Codable, Sendable {
    var weightDeltaKg: Double?
    var fatDeltaPercent: Double?
    var priorSundayTargetKg: Double?
    var adherenceLine: String
    var signalLines: [String]
    var summaryLine: String
}

struct MondaySundayGoal: Equatable, Codable, Sendable {
    var targetKg: Double
    var sundayDate: Date
    var weeklyDeltaKg: Double
    var pacingLine: String
    /// Catch-up / accelerate / aggressive. Defaults to aggressive for old caches.
    var modeRaw: String?

    var mode: WeeklyTargetMode {
        WeeklyTargetMode(rawValue: modeRaw ?? "") ?? .aggressive
    }
}

/// Cached Monday card payload for the ISO week.
struct MondayCardPayload: Equatable, Codable, Sendable {
    var weekKey: String
    var weighInSignature: String
    var currentKg: Double
    var progress: MondayWeekProgress
    var sundayGoal: MondaySundayGoal
    var encouragement: String
    var meals: String
    var diagnostic: String
    var usedNetwork: Bool
    var generatedAt: Date

    var isComplete: Bool {
        !encouragement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum MondayCardStore {
    private static let payloadKey = "thescale.mondayCard.payload"
    private static let priorSundayKey = "thescale.mondayCard.priorSundayTargetKg"

    static func load() -> MondayCardPayload? {
        guard let data = UserDefaults.standard.data(forKey: payloadKey),
              let payload = try? JSONDecoder().decode(MondayCardPayload.self, from: data)
        else { return nil }
        return payload
    }

    static func save(_ payload: MondayCardPayload) {
        if let existingData = UserDefaults.standard.data(forKey: payloadKey),
           let existing = try? JSONDecoder().decode(MondayCardPayload.self, from: existingData),
           existing.weekKey != payload.weekKey {
            // Rolling into a new ISO week: last card's Sunday target becomes adherence baseline.
            setPriorSundayTargetKg(existing.sundayGoal.targetKg)
        }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: payloadKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: payloadKey)
    }

    static var priorSundayTargetKg: Double? {
        let value = UserDefaults.standard.object(forKey: priorSundayKey) as? Double
        return value
    }

    static func setPriorSundayTargetKg(_ kg: Double?) {
        if let kg {
            UserDefaults.standard.set(kg, forKey: priorSundayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: priorSundayKey)
        }
    }
}

/// Trigger window + Sunday pacing + progress math for the Monday post-weigh card.
enum MondayCardEngine {
    /// Local morning window after a Monday weigh-in (inclusive start, exclusive end hour).
    static let morningHourStart = 4
    static let morningHourEnd = 12

    /// Gregorian calendar forced to Monday-first weeks (ISO-style), keeping the caller's time zone.
    static func mondayBasedCalendar(from calendar: Calendar = .current) -> Calendar {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// Local Monday 00:00 for the week containing `now` (Mon→Sun week).
    static func startOfWeekMonday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = mondayBasedCalendar(from: calendar)
        let startOfDay = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun … 7=Sat
        // Days since Monday: Mon=0 … Sun=6
        let daysFromMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    /// True when `date` falls on the Monday that opens the week containing `now`.
    static func isAnchoredToCurrentMonday(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let cal = mondayBasedCalendar(from: calendar)
        let monday = startOfWeekMonday(now: now, calendar: calendar)
        return cal.isDate(date, inSameDayAs: monday)
    }

    /// Weight at / carried into Monday: first Monday sample, else latest sample before Tuesday.
    static func weekStartWeightKg(
        from samples: [(kg: Double, date: Date)],
        weekStartMonday: Date,
        calendar: Calendar = .current
    ) -> Double? {
        let cal = mondayBasedCalendar(from: calendar)
        let mondayEnd = cal.date(byAdding: .day, value: 1, to: weekStartMonday)
            ?? weekStartMonday.addingTimeInterval(86_400)
        let onMonday = samples
            .filter { $0.date >= weekStartMonday && $0.date < mondayEnd }
            .sorted { $0.date < $1.date }
        if let first = onMonday.first { return first.kg }
        let prior = samples
            .filter { $0.date < mondayEnd }
            .sorted { $0.date < $1.date }
        return prior.last.map(\.kg)
    }

    /// Safe re-anchor: week always opens Monday 00:00. Never invent mid-week "loss"
    /// by rebasing week-start kg to today's baseline (preview/test wipe recovery).
    static func reconcileWeekStart(
        weekStartKg: Double?,
        weekStartDate: Date?,
        currentBaselineKg: Double?,
        history: [(kg: Double, date: Date)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeekStartReconcile {
        let cal = mondayBasedCalendar(from: calendar)
        let monday = startOfWeekMonday(now: now, calendar: calendar)
        let historyKg = weekStartWeightKg(
            from: history,
            weekStartMonday: monday,
            calendar: calendar
        )

        let storedInThisWeek: Bool = {
            guard let stored = weekStartDate else { return false }
            return cal.isDate(stored, equalTo: monday, toGranularity: .weekOfYear)
        }()
        let storedOnMonday = weekStartDate.map {
            isAnchoredToCurrentMonday($0, now: now, calendar: calendar)
        } ?? false

        // Correctly anchored this Monday → keep live progress.
        if storedOnMonday, let kg = weekStartKg {
            let dateNeedsNormalize = !(weekStartDate.map { cal.isDate($0, equalTo: monday, toGranularity: .minute) } ?? false)
            if dateNeedsNormalize {
                return WeekStartReconcile(
                    weekStartKg: kg,
                    weekStartDate: monday,
                    didChange: true,
                    reason: "normalize-monday-midnight"
                )
            }
            return WeekStartReconcile(
                weekStartKg: kg,
                weekStartDate: monday,
                didChange: false,
                reason: "ok"
            )
        }

        // Same Mon→Sun week but stamp was wrong (e.g. "today" after Monday-card preview).
        if storedInThisWeek {
            var kg = weekStartKg
            var reason = "reanchor-date-keep-kg"
            // Detect wipe-to-today: stamped kg ≈ live baseline while Health still has Monday's weight.
            if let stamped = weekStartKg,
               let baseline = currentBaselineKg,
               let mondayKg = historyKg,
               abs(stamped - baseline) <= 0.15,
               abs(mondayKg - stamped) > 0.05 {
                kg = mondayKg
                reason = "restore-monday-from-history"
            } else if kg == nil {
                kg = historyKg ?? currentBaselineKg
                reason = "reanchor-date-seed-kg"
            }
            let changed = kg != weekStartKg
                || !(weekStartDate.map { cal.isDate($0, equalTo: monday, toGranularity: .minute) } ?? false)
            return WeekStartReconcile(
                weekStartKg: kg,
                weekStartDate: monday,
                didChange: changed,
                reason: reason
            )
        }

        // Missing stamp or prior week → open this Monday from Health, never invent loss.
        let kg = historyKg ?? weekStartKg ?? currentBaselineKg
        let changed = kg != weekStartKg
            || !(weekStartDate.map { cal.isDate($0, equalTo: monday, toGranularity: .minute) } ?? false)
        return WeekStartReconcile(
            weekStartKg: kg,
            weekStartDate: monday,
            didChange: changed,
            reason: weekStartDate == nil ? "seed-monday" : "roll-to-monday"
        )
    }

    static func isMonday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: now) == 2
    }

    static func isMorningWindow(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= morningHourStart && hour < morningHourEnd
    }

    /// Production trigger: Monday + morning local time.
    static func shouldOfferAfterWeighIn(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        isMonday(now: now, calendar: calendar) && isMorningWindow(now: now, calendar: calendar)
    }

    static func weighInSignature(kg: Double, at date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date).timeIntervalSince1970
        return String(format: "%.2f@%.0f", kg, day)
    }

    /// Upcoming Sunday end-of-day local (this week's Sunday if not past; else next).
    static func targetSunday(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now) // 1=Sun … 7=Sat
        let daysUntilSunday: Int
        if weekday == 1 {
            daysUntilSunday = 0
        } else {
            daysUntilSunday = 8 - weekday
        }
        let start = calendar.startOfDay(for: now)
        let sundayStart = calendar.date(byAdding: .day, value: daysUntilSunday, to: start) ?? start
        // Noon Sunday as a stable display anchor.
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: sundayStart) ?? sundayStart
    }

    /// Pace current → ideal as hard as biology safely allows.
    /// Missed last Sunday → hardcore catch-up. Ahead → accelerate (no coast).
    static func sundayGoal(
        currentKg: Double,
        idealKg: Double,
        goalDate: Date?,
        fallbackWeeklyDeltaKg: Double,
        priorSundayTargetKg: Double? = MondayCardStore.priorSundayTargetKg,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MondaySundayGoal {
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: currentKg,
            idealKg: idealKg,
            goalDate: goalDate,
            priorSundayTargetKg: priorSundayTargetKg,
            fallbackWeeklyDeltaKg: fallbackWeeklyDeltaKg,
            now: now,
            calendar: calendar
        )
        return MondaySundayGoal(
            targetKg: hit.sundayTargetKg,
            sundayDate: hit.sundayDate,
            weeklyDeltaKg: hit.weeklyDeltaKg,
            pacingLine: hit.pacingLine,
            modeRaw: hit.mode.rawValue
        )
    }

    static func progress(
        weights: [HealthMetricSample],
        fats: [HealthMetricSample],
        currentKg: Double,
        priorSundayTargetKg: Double?,
        digest: FitnessDigest?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MondayWeekProgress {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        let priorWeights = weights.filter { $0.date >= weekAgo && $0.date < now }
        let startKg: Double? = {
            if let first = priorWeights.first { return first.value }
            if let older = weights.last(where: { $0.date < weekAgo }) { return older.value }
            return nil
        }()
        let weightDelta: Double? = startKg.map { currentKg - $0 }

        let priorFats = fats.filter { $0.date >= weekAgo && $0.date < now }
        let fatDelta: Double? = {
            guard let end = fats.last(where: { $0.date <= now })?.value else { return nil }
            if let start = priorFats.first?.value { return end - start }
            if let older = fats.last(where: { $0.date < weekAgo })?.value { return end - older }
            return nil
        }()

        let adherence: String = {
            guard let prior = priorSundayTargetKg else {
                return "No prior Sunday target on file."
            }
            let miss = currentKg - prior
            if abs(miss) <= 0.15 {
                return String(format: "Hit prior Sunday %.2f kg (within 0.15).", prior)
            }
            if miss > 0 {
                return String(format: "%.2f kg over prior Sunday %.2f.", miss, prior)
            }
            return String(format: "%.2f kg under prior Sunday %.2f.", abs(miss), prior)
        }()

        var signals: [String] = []
        if let digest {
            if let steps = digest.stepsToday {
                signals.append(String(format: "Steps today %.0f", steps))
            }
            if let kcal = digest.activeEnergyKcalToday {
                signals.append(String(format: "Active energy %.0f kcal", kcal))
            }
            if digest.workoutCountLast24h > 0 {
                signals.append("Workouts 24h \(digest.workoutCountLast24h)")
            } else if let last = digest.lastWorkout {
                signals.append("Last workout \(last.activityName)")
            }
            if let sleep = digest.sleepHoursLastNight {
                signals.append(String(format: "Sleep %.1f h", sleep))
            }
            if let hrv = digest.hrvSDNNMs {
                signals.append(String(format: "HRV %.0f ms", hrv))
            }
            if let recovery = digest.recovery {
                signals.append("Recovery \(recovery.band.rawValue)")
            }
        }
        if signals.isEmpty {
            signals.append("Health signals thin this pass.")
        }

        let summary: String = {
            if let delta = weightDelta {
                let fatBit: String = {
                    guard let fatDelta else { return "" }
                    return String(format: " · fat %+.1f%%", fatDelta)
                }()
                return String(format: "Last 7d weight %+.2f kg%@.", delta, fatBit)
            }
            return "First solid Monday baseline this week."
        }()

        return MondayWeekProgress(
            weightDeltaKg: weightDelta,
            fatDeltaPercent: fatDelta,
            priorSundayTargetKg: priorSundayTargetKg,
            adherenceLine: adherence,
            signalLines: Array(signals.prefix(5)),
            summaryLine: summary
        )
    }

    static func offlineCopy(
        name: String,
        progress: MondayWeekProgress,
        goal: MondaySundayGoal,
        diet: DietPreference,
        memoryBlock: String
    ) -> (encouragement: String, meals: String, diagnostic: String) {
        let who = name.isEmpty ? "Operator" : name
        let deltaBit: String = {
            if let d = progress.weightDeltaKg {
                return String(format: "Last week %+.2f kg.", d)
            }
            return "Fresh baseline."
        }()
        let encouragement: String = {
            switch goal.mode {
            case .hardcoreCatchUp:
                return "\(who), \(deltaBit) Hardcore catch-up. Sunday is \(String(format: "%.2f", goal.targetKg)) kg. Close the gap."
            case .accelerate:
                return "\(who), \(deltaBit) You're ahead. Sunday is \(String(format: "%.2f", goal.targetKg)) kg. Celebrate, then push."
            case .hold:
                return "\(who), \(deltaBit) Hold near \(String(format: "%.2f", goal.targetKg)) kg Sunday. Steady wins."
            case .aggressive:
                return "\(who), \(deltaBit) Sunday is \(String(format: "%.2f", goal.targetKg)) kg. Physics does not care about your feelings. Hit the number."
            }
        }()

        let meals: String = {
            let protein: String = {
                switch diet {
                case .vegan: return "Tofu / tempeh / lentils every plate."
                case .vegetarian: return "Eggs, dairy, legumes. Protein like you mean it."
                case .pescatarian: return "Fish + legumes; keep veg volume high."
                case .omnivore, .other: return "Palm-size protein each meal, veg first."
                }
            }()
            let ifHint = memoryBlock.lowercased().contains("fast") || memoryBlock.lowercased().contains("16/8")
                ? "Keep your IF window. No grazing after close."
                : "Pick a food window and close the kitchen after."
            return "Week pattern: \(protein) \(ifHint) One repeatable lunch, one repeatable dinner. Skip the novel."
        }()

        let diagnostic = """
        Sunday target \(String(format: "%.2f", goal.targetKg)) kg (\(String(format: "%+.2f", goal.weeklyDeltaKg)) kg).
        \(goal.pacingLine)
        \(progress.adherenceLine)
        Energy balance: if weight stalls while eating at maintenance, cut ~300-500 kcal/day or add a real walk deficit. ~7700 kcal ≈ 1 kg fat-ish; weekly rate is what the scale will show, not daily noise.
        Signals: \(progress.signalLines.joined(separator: " · ")).
        """

        return (encouragement, meals, CoachCopySanitize.clean(diagnostic))
    }

    /// Parse streamed Grok sections for the Monday card.
    static func parseSections(from raw: String) -> (encouragement: String, meals: String, diagnostic: String) {
        let cleaned = CoachCopySanitize.clean(raw)
        func section(_ name: String) -> String? {
            let markers = ["===\(name)===", "[\(name)]", "\(name):"]
            for marker in markers {
                guard let range = cleaned.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else {
                    continue
                }
                let after = cleaned[range.upperBound...]
                let nextMarkers = ["===ENCOURAGEMENT===", "===MEALS===", "===DIAGNOSTIC===", "[ENCOURAGEMENT]", "[MEALS]", "[DIAGNOSTIC]"]
                var end = after.endIndex
                for next in nextMarkers {
                    if next.lowercased().contains(name.lowercased()) { continue }
                    if let hit = after.range(of: next, options: [.caseInsensitive]) {
                        end = min(end, hit.lowerBound)
                    }
                }
                let body = String(after[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { return CoachCopySanitize.clean(body) }
            }
            return nil
        }

        let encouragement = section("ENCOURAGEMENT") ?? ""
        let meals = section("MEALS") ?? ""
        let diagnostic = section("DIAGNOSTIC") ?? ""
        if encouragement.isEmpty && meals.isEmpty && diagnostic.isEmpty {
            // Unstructured blob → treat as diagnostic, keep short encouragement empty for UI filler.
            return ("", "", cleaned)
        }
        return (encouragement, meals, diagnostic)
    }
}
