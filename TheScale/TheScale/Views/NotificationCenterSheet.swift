import SwiftUI
import UserNotifications

/// Pending + delivered local notifications for The Scale.
struct NotificationCenterSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pending: [PendingNotifRow] = []
    @State private var delivered: [UNNotification] = []
    @State private var isLoading = true
    @State private var authLine = ""
    @State private var authDenied = false
    @State private var testNote: String?

    private struct PendingNotifRow: Identifiable {
        let id: String
        let title: String
        let body: String
        let meta: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text(authLine)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(authDenied ? Color.orange : .secondary)
                                .listRowBackground(Color.clear)
                            if authDenied {
                                Button("Open System Settings") {
                                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }

                        Section {
                            Button {
                                Task {
                                    let ok = await MorningWeighDrillScheduler.forceFireTest(
                                        profileName: session.profile.greetingName
                                    )
                                    testNote = ok
                                        ? "Test 💩 drill in ~2s (Time Sensitive). Leave the app or lock the phone."
                                        : "Blocked. Allow notifications first."
                                    await reload()
                                }
                            } label: {
                                Label("Send test drill now", systemImage: "bell.and.waves.left.and.right")
                            }
                            .accessibilityIdentifier("alerts.sendTestDrill")
                            if let testNote {
                                Text(testNote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Debug")
                        }

                        Section("Pending / scheduled") {
                            if pending.isEmpty {
                                Text("Nothing queued. If Morning weigh is on, open Settings → Allow, then pull to refresh.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(pending) { row in
                                    notificationRow(
                                        title: row.title,
                                        body: row.body,
                                        meta: row.meta
                                    )
                                }
                            }
                        }

                        Section("Recent") {
                            if delivered.isEmpty {
                                Text("No recent deliveries.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(delivered, id: \.request.identifier) { note in
                                    notificationRow(
                                        title: note.request.content.title,
                                        body: note.request.content.body,
                                        meta: note.date.formatted(date: .abbreviated, time: .shortened)
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
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

    private func notificationRow(title: String, body: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.isEmpty ? "The Scale" : title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(meta)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        isLoading = true
        let detail = await TrendNotificationScheduler.authorizationStatusDetail()
        authLine = detail.line
        authDenied = detail.isDenied
        let pendingReqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let deliveredNotes = await UNUserNotificationCenter.current().deliveredNotifications()
        pending = pendingReqs.map { req in
            PendingNotifRow(
                id: req.identifier,
                title: req.content.title,
                body: req.content.body,
                meta: triggerMeta(req)
            )
        }
        .sorted { $0.meta < $1.meta }
        delivered = deliveredNotes.sorted { $0.date > $1.date }
        isLoading = false
    }

    private func triggerMeta(_ request: UNNotificationRequest) -> String {
        let idHint: String = {
            switch request.identifier {
            case MorningWeighDrillScheduler.fallbackRequestId: return "morning fallback"
            case MorningWeighDrillScheduler.requestId: return "sleep-wake drill"
            case MorningWeighDrillScheduler.testRequestId: return "test drill"
            case TrendNotificationScheduler.weeklyGoalId: return "weekly goal"
            case TrendNotificationScheduler.badTrendId: return "bad trend"
            default:
                if request.identifier.hasPrefix(CoachReminderScheduler.notificationIdPrefix)
                    || request.identifier == CoachReminderScheduler.wakeReminderId
                {
                    return "coach reminder"
                }
                return request.identifier
            }
        }()
        if let cal = request.trigger as? UNCalendarNotificationTrigger,
           let next = cal.nextTriggerDate()
        {
            return "\(idHint) · \(next.formatted(date: .abbreviated, time: .shortened))"
        }
        if let interval = request.trigger as? UNTimeIntervalNotificationTrigger,
           let next = interval.nextTriggerDate()
        {
            return "\(idHint) · \(next.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(idHint) · \(String(describing: type(of: request.trigger)))"
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
