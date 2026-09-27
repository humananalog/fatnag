import SwiftUI
import UserNotifications

/// Pending + delivered local notifications for The Scale.
/// Clear section hierarchy: status → coming up → recent (DEBUG: developer tools).
struct NotificationCenterSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var pending: [PendingNotifRow] = []
    @State private var delivered: [UNNotification] = []
    @State private var isLoading = true
    @State private var authLine = ""
    @State private var authDenied = false
    #if DEBUG
    @State private var testNote: String?
    @State private var showDeveloperTools = false
    #endif

    private struct PendingNotifRow: Identifiable {
        let id: String
        let title: String
        let body: String
        let kindLabel: String
        let whenLabel: String
    }

    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.95, blue: 0.92)
            : Color(red: 0.08, green: 0.09, blue: 0.12)
    }

    private var mist: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.62)
            : Color.black.opacity(0.48)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading alerts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            permissionCard
                        } header: {
                            sectionHeader("Permission", systemImage: "lock.shield")
                        } footer: {
                            Text("Focus and Do Not Disturb can still silence banners.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }

                        Section {
                            if pending.isEmpty {
                                emptyRow(
                                    title: "Nothing queued",
                                    detail: "Turn on Morning weigh or weekly reminders in Settings, then pull to refresh."
                                )
                            } else {
                                ForEach(pending) { row in
                                    notificationRow(
                                        title: row.title,
                                        body: row.body,
                                        kindLabel: row.kindLabel,
                                        whenLabel: row.whenLabel
                                    )
                                }
                            }
                        } header: {
                            sectionHeader("Coming up", systemImage: "calendar")
                        } footer: {
                            Text(pending.isEmpty
                                  ? "Scheduled alerts appear here before they fire."
                                  : "\(pending.count) scheduled")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }

                        Section {
                            if delivered.isEmpty {
                                emptyRow(
                                    title: "No recent deliveries",
                                    detail: "After Coach pings land, they show up here."
                                )
                            } else {
                                ForEach(delivered, id: \.request.identifier) { note in
                                    notificationRow(
                                        title: note.request.content.title,
                                        body: note.request.content.body,
                                        kindLabel: kindLabel(for: note.request.identifier),
                                        whenLabel: note.date.formatted(date: .abbreviated, time: .shortened)
                                    )
                                }
                            }
                        } header: {
                            sectionHeader("Recently delivered", systemImage: "tray.full")
                        }

                        #if DEBUG
                        Section {
                            DisclosureGroup(isExpanded: $showDeveloperTools) {
                                Button {
                                    Task {
                                        let ok = await MorningWeighDrillScheduler.forceFireTest(
                                            profileName: session.profile.greetingName
                                        )
                                        testNote = ok
                                            ? "Test drill in about 2 seconds. Leave the app or lock the phone."
                                            : "Blocked. Allow notifications first."
                                        await reload()
                                    }
                                } label: {
                                    Label("Send test drill now", systemImage: "bell.and.waves.left.and.right")
                                }
                                .accessibilityIdentifier("alerts.sendTestDrill")

                                if let testNote {
                                    Text(testNote)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(mist)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } label: {
                                Label("Developer tools", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.85))
                            }
                        } footer: {
                            Text("QA only. Not needed for daily use.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }
                        #endif
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .task {
                await session.considerMorningWeighDrill()
                await reload()
            }
        }
    }

    // MARK: - Rows

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: authDenied ? "bell.slash.fill" : "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(authDenied ? Color.orange : Color.green.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(
                        (authDenied ? Color.orange : Color.green).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(authDenied ? "Alerts blocked" : "Alerts allowed")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(authLine)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(authDenied ? Color.orange : mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if authDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open System Settings")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(ink.opacity(0.72))
            .textCase(nil)
    }

    private func emptyRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(mist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func notificationRow(
        title: String,
        body: String,
        kindLabel: String,
        whenLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kindLabel)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(ink.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ink.opacity(colorScheme == .dark ? 0.14 : 0.06), in: Capsule())
                Spacer(minLength: 0)
                Text(whenLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(mist)
                    .multilineTextAlignment(.trailing)
            }

            Text(title.isEmpty ? "The Scale" : title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)

            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        let detail = await TrendNotificationScheduler.authorizationStatusDetail()
        authLine = detail.line
        authDenied = detail.isDenied
        let pendingReqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let deliveredNotes = await UNUserNotificationCenter.current().deliveredNotifications()
        pending = pendingReqs.map { req in
            let parts = triggerParts(req)
            return PendingNotifRow(
                id: req.identifier,
                title: req.content.title,
                body: req.content.body,
                kindLabel: parts.kind,
                whenLabel: parts.when
            )
        }
        .sorted { $0.whenLabel < $1.whenLabel }
        delivered = deliveredNotes.sorted { $0.date > $1.date }
        isLoading = false
    }

    private func kindLabel(for identifier: String) -> String {
        switch identifier {
        case MorningWeighDrillScheduler.fallbackRequestId: return "Morning fallback"
        case MorningWeighDrillScheduler.requestId: return "Morning drill"
        case MorningWeighDrillScheduler.testRequestId: return "Test drill"
        case TrendNotificationScheduler.weeklyGoalId: return "Weekly goal"
        case TrendNotificationScheduler.badTrendId: return "Trend check"
        default:
            if identifier.hasPrefix(CoachReminderScheduler.notificationIdPrefix)
                || identifier == CoachReminderScheduler.wakeReminderId
            {
                return "Coach reminder"
            }
            return "Alert"
        }
    }

    private func triggerParts(_ request: UNNotificationRequest) -> (kind: String, when: String) {
        let kind = kindLabel(for: request.identifier)
        if let cal = request.trigger as? UNCalendarNotificationTrigger,
           let next = cal.nextTriggerDate()
        {
            return (kind, next.formatted(date: .abbreviated, time: .shortened))
        }
        if let interval = request.trigger as? UNTimeIntervalNotificationTrigger,
           let next = interval.nextTriggerDate()
        {
            return (kind, next.formatted(date: .abbreviated, time: .shortened))
        }
        return (kind, "Queued")
    }
}

/// Compact bell for the home brand row.
struct HomeNotificationBell: View {
    @Binding var isPresented: Bool
    var badgeCount: Int = 0

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: badgeCount > 0 ? "bell.badge.fill" : "bell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ScaleChrome.ink.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .scaleGlassCircle()

                if badgeCount > 0 {
                    Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.95), in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badgeCount > 0 ? "Alerts, \(badgeCount) pending" : "Alerts")
    }
}
