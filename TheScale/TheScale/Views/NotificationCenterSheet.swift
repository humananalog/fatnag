import SwiftUI
import UserNotifications

/// Pending + delivered local notifications for The Scale.
struct NotificationCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: [UNNotificationRequest] = []
    @State private var delivered: [UNNotification] = []
    @State private var isLoading = true
    @State private var authLine = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text(authLine)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }

                        Section("Pending") {
                            if pending.isEmpty {
                                Text("Nothing queued.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(pending, id: \.identifier) { request in
                                    notificationRow(
                                        title: request.content.title,
                                        body: request.content.body,
                                        meta: request.trigger.map { String(describing: type(of: $0)) } ?? "soon"
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
            .task { await reload() }
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: authLine = "Notifications on. Time Sensitive allowed when system grants it."
        case .provisional: authLine = "Provisional delivery. Enable Alerts in Settings for full pings."
        case .denied: authLine = "Notifications off. Open Settings to allow alerts."
        case .notDetermined: authLine = "Not asked yet. Weigh or open Settings to enable."
        case .ephemeral: authLine = "Ephemeral authorization active."
        @unknown default: authLine = "Notification status unknown."
        }
        // Sequential UNUserNotificationCenter reads: center is not Sendable; avoid async-let races.
        let pendingReqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let deliveredNotes = await UNUserNotificationCenter.current().deliveredNotifications()
        pending = pendingReqs
        delivered = deliveredNotes.sorted { $0.date > $1.date }
        isLoading = false
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
