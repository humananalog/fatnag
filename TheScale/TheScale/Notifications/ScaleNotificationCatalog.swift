import Foundation
import UserNotifications

/// Canonical notification families for FATNAG (iOS 27 local UN APIs).
enum ScaleNotificationKind: String, Sendable {
    case coachWake
    case coachReminder
    case badTrend
    case weeklyGoal
    case fitnessInterval
    case watchWear
    case preSleepHR
    case sample
    /// Out of bed / left bedtime: sergeant weigh-now drill.
    case morningWeigh

    var categoryId: String {
        switch self {
        case .coachWake, .coachReminder: return ScaleNotificationCategoryID.coachReminder
        case .morningWeigh: return ScaleNotificationCategoryID.morningWeigh
        case .badTrend: return ScaleNotificationCategoryID.badTrend
        case .weeklyGoal: return ScaleNotificationCategoryID.weeklyGoal
        case .fitnessInterval: return ScaleNotificationCategoryID.fitnessInterval
        case .watchWear, .preSleepHR: return ScaleNotificationCategoryID.fitnessSignal
        case .sample: return ScaleNotificationCategoryID.sample
        }
    }

    var threadId: String {
        switch self {
        case .coachWake, .coachReminder, .morningWeigh: return "thescale.coach"
        case .badTrend, .weeklyGoal: return "thescale.trend"
        case .fitnessInterval, .watchWear, .preSleepHR: return "thescale.fitness"
        case .sample: return "thescale.sample"
        }
    }

    /// Time Sensitive only for true wake pings the user asked to land on time.
    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .coachWake, .morningWeigh: return .timeSensitive
        case .coachReminder, .badTrend, .watchWear, .preSleepHR, .sample:
            return .active
        case .weeklyGoal, .fitnessInterval:
            return .passive
        }
    }

    var relevanceScore: Double {
        switch self {
        case .coachWake, .morningWeigh: return 1.0
        case .sample: return 0.95
        case .badTrend, .watchWear, .preSleepHR: return 0.85
        case .coachReminder: return 0.8
        case .weeklyGoal: return 0.55
        case .fitnessInterval: return 0.35
        }
    }

    var destination: ScaleNotificationDestination {
        switch self {
        case .coachWake, .coachReminder, .fitnessInterval, .watchWear, .preSleepHR, .sample:
            return .coach
        case .morningWeigh:
            return .weigh
        case .badTrend:
            return .history
        case .weeklyGoal:
            return .progress
        }
    }

    /// Communication-style avatar presentation (Coach sender).
    var usesCommunicationStyle: Bool {
        switch self {
        case .coachWake, .coachReminder, .watchWear, .preSleepHR, .sample, .morningWeigh:
            return true
        case .badTrend, .weeklyGoal, .fitnessInterval:
            return false
        }
    }

    var visualStyle: ScaleNotificationVisualStyle {
        switch self {
        case .badTrend: return .trendUp
        case .weeklyGoal: return .goal
        case .watchWear: return .watch
        case .preSleepHR: return .heart
        case .coachWake, .coachReminder, .morningWeigh: return .coach
        case .fitnessInterval: return .pulse
        case .sample: return .sample
        }
    }
}

enum ScaleNotificationCategoryID {
    static let coachReminder = "THESCALE_COACH_REMINDER"
    static let morningWeigh = "THESCALE_MORNING_WEIGH"
    static let badTrend = "THESCALE_BAD_TREND"
    static let weeklyGoal = "THESCALE_WEEKLY_GOAL"
    static let fitnessInterval = "THESCALE_FITNESS_INTERVAL"
    static let fitnessSignal = "THESCALE_FITNESS_SIGNAL"
    static let sample = "THESCALE_SAMPLE"
}

enum ScaleNotificationActionID {
    static let openCoach = "THESCALE_OPEN_COACH"
    static let openProgress = "THESCALE_OPEN_PROGRESS"
    static let openHistory = "THESCALE_OPEN_HISTORY"
    static let openWeigh = "THESCALE_OPEN_WEIGH"
    static let snooze10 = "THESCALE_SNOOZE_10"
}

enum ScaleNotificationDestination: String, Sendable {
    case coach
    case progress
    case history
    case settings
    case weigh
}

enum ScaleNotificationUserInfoKey {
    static let destination = "thescale.destination"
    static let kind = "thescale.kind"
    static let visualHint = "thescale.visualHint"
    static let glanceTitle = "thescale.glanceTitle"
    static let phoneBody = "thescale.phoneBody"
}

enum ScaleNotificationVisualStyle: String, Sendable {
    case coach
    case trendUp
    case goal
    case watch
    case heart
    case pulse
    case sample
}

/// Registers actionable categories once at launch (iOS 27 UNNotificationCategory).
enum ScaleNotificationCategories {
    static func register() {
        let openCoach = UNNotificationAction(
            identifier: ScaleNotificationActionID.openCoach,
            title: "Open Coach",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "sparkles")
        )
        let openProgress = UNNotificationAction(
            identifier: ScaleNotificationActionID.openProgress,
            title: "Open Progress",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "flag.checkered")
        )
        let openHistory = UNNotificationAction(
            identifier: ScaleNotificationActionID.openHistory,
            title: "Open History",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "chart.xyaxis.line")
        )
        let openWeigh = UNNotificationAction(
            identifier: ScaleNotificationActionID.openWeigh,
            title: "Weigh now",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "scalemass.fill")
        )
        let snooze = UNNotificationAction(
            identifier: ScaleNotificationActionID.snooze10,
            title: "Snooze 10 min",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "clock")
        )

        let coach = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.coachReminder,
            actions: [openCoach, snooze],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Coach reminder",
            categorySummaryFormat: "%u Coach reminders",
            options: [.customDismissAction, .hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        let morning = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.morningWeigh,
            actions: [openWeigh, snooze],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Morning weigh",
            categorySummaryFormat: "%u morning weighs",
            options: [.customDismissAction, .hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        let badTrend = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.badTrend,
            actions: [openHistory, openProgress, snooze],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Scale trend check",
            categorySummaryFormat: "%u trend alerts",
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        let weekly = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.weeklyGoal,
            actions: [openProgress, openCoach],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Weekly mini-goal",
            categorySummaryFormat: "%u goal reminders",
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        let interval = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.fitnessInterval,
            actions: [openCoach],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Fitness check",
            categorySummaryFormat: "%u fitness nudges",
            options: [.hiddenPreviewsShowTitle]
        )
        let signal = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.fitnessSignal,
            actions: [openCoach, snooze],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Watch / sleep signal",
            categorySummaryFormat: "%u Watch signals",
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        let sample = UNNotificationCategory(
            identifier: ScaleNotificationCategoryID.sample,
            actions: [openCoach, openProgress],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Sample notification",
            categorySummaryFormat: "%u sample pings",
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            coach, morning, badTrend, weekly, interval, signal, sample
        ])
    }
}
