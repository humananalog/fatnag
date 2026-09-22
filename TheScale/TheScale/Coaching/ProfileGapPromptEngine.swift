import Foundation

/// Soft, non-spammy prompts for blank lifestyle fields. Completes the picture over time.
enum ProfileGapPromptEngine {
    /// Minimum days between any soft profile sheet.
    static let daysBetweenAnyPrompt: Double = 5
    /// Minimum days before re-asking the same gap after "Not now".
    static let daysBetweenSameGap: Double = 18
    /// Never queue more than one gap per calendar day.
    static let maxPromptsPerDay: Int = 1

    /// Which gap (if any) to ask now. Prefer location → avoidances → diet.
    static func nextGap(
        profile: UserBodyProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProfileGapKind? {
        let state = ProfileGapPromptStore.load()
        if let lastAny = state.lastAnyPromptAt,
           now.timeIntervalSince(lastAny) < daysBetweenAnyPrompt * 86_400 {
            return nil
        }
        if let day = state.lastPromptDayKey,
           day == dayKey(now: now, calendar: calendar),
           state.promptsOnLastDay >= maxPromptsPerDay {
            return nil
        }

        let ordered: [ProfileGapKind] = [.location, .foodAvoidances, .diet]
        for kind in ordered {
            guard isMissing(kind, profile: profile) else { continue }
            if let last = state.lastPromptAt[kind.rawValue],
               now.timeIntervalSince(last) < daysBetweenSameGap * 86_400 {
                continue
            }
            return kind
        }
        return nil
    }

    static func isMissing(_ kind: ProfileGapKind, profile: UserBodyProfile) -> Bool {
        switch kind {
        case .location:
            return profile.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .foodAvoidances:
            if profile.foodAvoidancesConfirmed { return false }
            return profile.foodAvoidances.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .diet:
            return !profile.dietPreferenceConfirmed
        }
    }

    static func recordPresented(_ kind: ProfileGapKind, now: Date = Date(), calendar: Calendar = .current) {
        var state = ProfileGapPromptStore.load()
        let key = dayKey(now: now, calendar: calendar)
        if state.lastPromptDayKey == key {
            state.promptsOnLastDay += 1
        } else {
            state.lastPromptDayKey = key
            state.promptsOnLastDay = 1
        }
        state.lastAnyPromptAt = now
        state.lastPromptAt[kind.rawValue] = now
        ProfileGapPromptStore.save(state)
    }

    static func recordSaved(_ kind: ProfileGapKind, now: Date = Date()) {
        var state = ProfileGapPromptStore.load()
        state.lastPromptAt[kind.rawValue] = now
        state.lastAnyPromptAt = now
        // Mark as "answered" by pushing same-gap cooldown far enough via timestamp;
        // missing check will clear the gap once profile is filled.
        ProfileGapPromptStore.save(state)
    }

    static func recordSkipped(_ kind: ProfileGapKind, now: Date = Date()) {
        recordPresented(kind, now: now)
    }

    private static func dayKey(now: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

struct ProfileGapPromptState: Equatable, Codable, Sendable {
    var lastAnyPromptAt: Date?
    var lastPromptAt: [String: Date]
    var lastPromptDayKey: String?
    var promptsOnLastDay: Int

    static let empty = ProfileGapPromptState(
        lastAnyPromptAt: nil,
        lastPromptAt: [:],
        lastPromptDayKey: nil,
        promptsOnLastDay: 0
    )
}

enum ProfileGapPromptStore {
    private static let key = "thescale.profileGapPrompt.v1"

    static func load() -> ProfileGapPromptState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ProfileGapPromptState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    static func save(_ state: ProfileGapPromptState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
