import SwiftUI
import UserNotifications

/// Pending + delivered local notifications for FATNAG.
/// Clear section hierarchy: status → coming up → recent.
struct NotificationCenterSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var pending: [PendingNotifRow] = []
    @State private var delivered: [DeliveredNotifRow] = []
    @State private var archived: [ArchivedAlert] = []
    @State private var isLoading = true
    @State private var authLine = ""
    @State private var authDenied = false

    private struct PendingNotifRow: Identifiable {
        let id: String
        let title: String
        let body: String
        let kindLabel: String
        let whenLabel: String
    }

    private struct DeliveredNotifRow: Identifiable {
        let id: String
        let requestId: String
        let title: String
        let body: String
        let kindLabel: String
        let whenLabel: String
        let deliveredAt: Date
        let destination: ScaleNotificationDestination
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
                    ProgressView(AppLanguageStore.text("notif.loading", default: "Loading alerts..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            permissionCard
                        } header: {
                            sectionHeader(
                                AppLanguageStore.text("notif.permission", default: "Permission"),
                                systemImage: "lock.shield"
                            )
                        } footer: {
                            Text(AppLanguageStore.text("notif.focus_footer", default: "Focus and Do Not Disturb can still silence banners."))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }

                        Section {
                            if pending.isEmpty {
                                emptyRow(
                                    title: AppLanguageStore.text("notif.empty_queued", default: "Nothing queued"),
                                    detail: AppLanguageStore.text("notif.empty_queued_detail", default: "Turn on Morning weigh or weekly reminders in Settings, then pull to refresh.")
                                )
                            } else {
                                ForEach(pending) { row in
                                    notificationRow(
                                        title: row.title,
                                        body: row.body,
                                        kindLabel: row.kindLabel,
                                        whenLabel: row.whenLabel
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        deleteButton { Task { await deletePending(row) } }
                                    }
                                }
                            }
                        } header: {
                            sectionHeader(
                                AppLanguageStore.text("notif.coming_up", default: "Coming up"),
                                systemImage: "calendar"
                            )
                        } footer: {
                            Text(pending.isEmpty
                                  ? AppLanguageStore.text("notif.scheduled_footer", default: "Scheduled alerts appear here before they fire.")
                                  : String(
                                        format: AppLanguageStore.text("notif.scheduled_count", default: "%d scheduled"),
                                        pending.count
                                    ))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }

                        Section {
                            if delivered.isEmpty {
                                emptyRow(
                                    title: AppLanguageStore.text("notif.empty_active", default: "Nothing active"),
                                    detail: AppLanguageStore.text("notif.empty_active_detail", default: "Acknowledged alerts move to Archive.")
                                )
                            } else {
                                ForEach(delivered) { row in
                                    Button {
                                        Task { await openAndAcknowledge(row) }
                                    } label: {
                                        notificationRow(
                                            title: row.title,
                                            body: row.body,
                                            kindLabel: row.kindLabel,
                                            whenLabel: row.whenLabel
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        deleteButton { Task { await deleteActive(row) } }
                                        Button {
                                            Task { await acknowledge(row) }
                                        } label: {
                                            Label(
                                                AppLanguageStore.text("notif.acknowledge", default: "Acknowledge"),
                                                systemImage: "archivebox"
                                            )
                                        }
                                        .tint(Color(red: 0.18, green: 0.52, blue: 0.62))
                                    }
                                }
                            }
                        } header: {
                            sectionHeader(
                                AppLanguageStore.text("notif.active", default: "Active"),
                                systemImage: "tray.full"
                            )
                        } footer: {
                            Text(AppLanguageStore.text("notif.active_footer", default: "Tap to open the related page. Swipe left to delete or archive."))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                        }

                        if !archived.isEmpty {
                            Section {
                                ForEach(archived) { item in
                                    notificationRow(
                                        title: item.title,
                                        body: item.body,
                                        kindLabel: kindLabel(for: item.requestId),
                                        whenLabel: item.acknowledgedAt.formatted(date: .abbreviated, time: .shortened)
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        deleteButton { deleteArchived(item) }
                                    }
                                }
                            } header: {
                                sectionHeader(
                                    AppLanguageStore.text("notif.archive", default: "Archive"),
                                    systemImage: "archivebox"
                                )
                            } footer: {
                                Text(String(
                                    format: AppLanguageStore.text("notif.archive_count", default: "%d acknowledged"),
                                    archived.count
                                ))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(mist)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle(AppLanguageStore.text("notif.title", default: "Alerts"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageStore.text("common.done", default: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(AppLanguageStore.text("common.refresh", default: "Refresh"))
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
                    Text(authDenied
                          ? AppLanguageStore.text("notif.blocked", default: "Alerts blocked")
                          : AppLanguageStore.text("notif.allowed", default: "Alerts allowed"))
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
                    Text(AppLanguageStore.text("notif.open_settings", default: "Open System Settings"))
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

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label(AppLanguageStore.text("notif.delete", default: "Delete"), systemImage: "trash")
        }
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

            Text(title.isEmpty ? "fatnag" : title)
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
        #if DEBUG
        if session.isDemoPersonaActive || PromoCaptureMode.isActive {
            applyDemoRoastRows()
            isLoading = false
            return
        }
        #endif
        let detail = await TrendNotificationScheduler.authorizationStatusDetail()
        authLine = detail.line
        authDenied = detail.isDenied
        let pendingReqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let deliveredNotes = await UNUserNotificationCenter.current().deliveredNotifications()
        let archive = NotificationArchiveStore.load()
        archived = archive
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
        delivered = deliveredNotes
            .sorted { $0.date > $1.date }
            .filter {
                !NotificationArchiveStore.isAcknowledged(
                    requestId: $0.request.identifier,
                    deliveredAt: $0.date,
                    in: archive
                )
            }
            .map { note in
                DeliveredNotifRow(
                    id: "\(note.request.identifier)-\(note.date.timeIntervalSince1970)",
                    requestId: note.request.identifier,
                    title: note.request.content.title,
                    body: note.request.content.body,
                    kindLabel: kindLabel(for: note.request.identifier),
                    whenLabel: note.date.formatted(date: .abbreviated, time: .shortened),
                    deliveredAt: note.date,
                    destination: destination(for: note.request.content, requestId: note.request.identifier)
                )
            }
        isLoading = false
    }

    private func openAndAcknowledge(_ row: DeliveredNotifRow) async {
        await acknowledge(row)
        dismiss()
        session.handleNotificationDestination(row.destination)
    }

    private func acknowledge(_ row: DeliveredNotifRow) async {
        #if DEBUG
        if session.isDemoPersonaActive || PromoCaptureMode.isActive {
            delivered.removeAll { $0.id == row.id }
            return
        }
        #endif
        NotificationArchiveStore.acknowledge(
            requestId: row.requestId,
            title: row.title,
            body: row.body,
            deliveredAt: row.deliveredAt
        )
        await reload()
    }

    private func deleteActive(_ row: DeliveredNotifRow) async {
        #if DEBUG
        if session.isDemoPersonaActive || PromoCaptureMode.isActive {
            delivered.removeAll { $0.id == row.id }
            return
        }
        #endif
        delivered.removeAll { $0.id == row.id }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [row.requestId])
        NotificationCenter.default.post(name: .fatnagAlertsDidChange, object: nil)
    }

    private func deletePending(_ row: PendingNotifRow) async {
        #if DEBUG
        if session.isDemoPersonaActive || PromoCaptureMode.isActive {
            pending.removeAll { $0.id == row.id }
            return
        }
        #endif
        pending.removeAll { $0.id == row.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [row.id])
        NotificationCenter.default.post(name: .fatnagAlertsDidChange, object: nil)
    }

    private func deleteArchived(_ item: ArchivedAlert) {
        archived.removeAll { $0.id == item.id }
        NotificationArchiveStore.delete(id: item.id)
    }

    #if DEBUG
    /// Marketing-ready roast / vulgar Coach alerts (sex-tuned).
    private func applyDemoRoastRows() {
        authLine = "Demo alerts (DEBUG). Real banners need permission on device."
        authDenied = false
        let name = session.profile.greetingName
        let sex = session.profile.sex
        let kg = session.healthBaselineKg.map {
            UnitFormat.massString($0, system: session.preferredUnits, fractionDigits: 1)
        } ?? "scale"
        switch sex {
        case .male:
            pending = [
                PendingNotifRow(
                    id: "demo.pending.morning",
                    title: "Step on it",
                    body: "\(name). Morning weigh. No excuses, no second coffee first.",
                    kindLabel: "Morning drill",
                    whenLabel: "Tomorrow 7:05"
                )
            ]
            delivered = [
                DeliveredNotifRow(
                    id: "demo.delivered.spike",
                    requestId: "demo.delivered.spike",
                    title: "Salt bomb",
                    body: "\(name). That \(kg) bump is weekend bullshit, not new fat. Drink water, hit protein, weigh tomorrow.",
                    kindLabel: "Red card",
                    whenLabel: "Today 8:12",
                    deliveredAt: Date(),
                    destination: .progress
                ),
                DeliveredNotifRow(
                    id: "demo.delivered.trend",
                    requestId: "demo.delivered.trend",
                    title: "−380g kept",
                    body: "\(name). Week is working. Don't blow it with a victory pastry like an idiot.",
                    kindLabel: "Trend check",
                    whenLabel: "Yesterday 18:40",
                    deliveredAt: Date(),
                    destination: .history
                ),
                DeliveredNotifRow(
                    id: "demo.delivered.watch",
                    requestId: "demo.delivered.watch",
                    title: "Watch off",
                    body: "\(name). No HR all day. Strap the damn watch or stop pretending you're training.",
                    kindLabel: "Watch signal",
                    whenLabel: "Yesterday 21:05",
                    deliveredAt: Date(),
                    destination: .coach
                ),
            ]
        case .female:
            pending = [
                PendingNotifRow(
                    id: "demo.pending.morning",
                    title: "Morning weigh",
                    body: "\(name), gentle reminder: same-time weigh tomorrow. You've got this.",
                    kindLabel: "Morning drill",
                    whenLabel: "Tomorrow 7:05"
                )
            ]
            delivered = [
                DeliveredNotifRow(
                    id: "demo.delivered.spike",
                    requestId: "demo.delivered.spike",
                    title: "Noise, not doom",
                    body: "\(name), that \(kg) blip is salt and cycle - not a relapse. Hold the line. Proud of you showing up.",
                    kindLabel: "Red card",
                    whenLabel: "Today 8:12",
                    deliveredAt: Date(),
                    destination: .progress
                ),
                DeliveredNotifRow(
                    id: "demo.delivered.trend",
                    requestId: "demo.delivered.trend",
                    title: "−380g kept",
                    body: "\(name), the week slope is down. Keep the protein plates and the walk after lunch.",
                    kindLabel: "Trend check",
                    whenLabel: "Yesterday 18:40",
                    deliveredAt: Date(),
                    destination: .history
                ),
                DeliveredNotifRow(
                    id: "demo.delivered.coach",
                    requestId: "demo.delivered.coach",
                    title: "Coach check",
                    body: "\(name), you showed up. That's the hard part. Eat the plan, ignore the panic edit.",
                    kindLabel: "Coach reminder",
                    whenLabel: "Yesterday 12:20",
                    deliveredAt: Date(),
                    destination: .coach
                ),
            ]
        }
    }
    #endif

    private func destination(
        for content: UNNotificationContent,
        requestId: String
    ) -> ScaleNotificationDestination {
        if let raw = content.userInfo[ScaleNotificationUserInfoKey.destination] as? String,
           let dest = ScaleNotificationDestination(rawValue: raw) {
            return dest
        }
        if let target = content.targetContentIdentifier,
           let dest = ScaleNotificationDestination(rawValue: target) {
            return dest
        }
        if let kindRaw = content.userInfo[ScaleNotificationUserInfoKey.kind] as? String,
           let kind = ScaleNotificationKind(rawValue: kindRaw) {
            return kind.destination
        }
        return destinationFallback(forRequestId: requestId)
    }

    private func destinationFallback(forRequestId identifier: String) -> ScaleNotificationDestination {
        switch identifier {
        case MorningWeighDrillScheduler.fallbackRequestId,
             MorningWeighDrillScheduler.requestId,
             MorningWeighDrillScheduler.testRequestId:
            return .weigh
        case TrendNotificationScheduler.weeklyGoalId:
            return .progress
        case TrendNotificationScheduler.badTrendId:
            return .history
        default:
            if identifier.hasPrefix("thescale.fitness-trigger.") {
                return .coach
            }
            return .coach
        }
    }

    private func kindLabel(for identifier: String) -> String {
        switch identifier {
        case MorningWeighDrillScheduler.fallbackRequestId: return "Morning fallback"
        case MorningWeighDrillScheduler.requestId: return "Morning drill"
        case MorningWeighDrillScheduler.testRequestId: return "Test drill"
        case TrendNotificationScheduler.weeklyGoalId: return "Weekly goal"
        case TrendNotificationScheduler.badTrendId: return "Trend check"
        case WeighMissLadderScheduler.eveningId: return "Evening miss"
        case WeighMissLadderScheduler.streakId: return "Miss streak"
        case WeighMissLadderScheduler.mondaySkipId: return "Monday skip"
        case WeighMissLadderScheduler.sundayWrapId: return "Sunday wrap"
        case "thescale.key-coach-moment": return "Key moment"
        case GrokFitnessMonitor.intervalNotifyId, GrokFitnessMonitor.activityPulseId: return "Nag"
        default:
            if identifier.hasPrefix(CoachReminderScheduler.notificationIdPrefix)
                || identifier == CoachReminderScheduler.wakeReminderId
            {
                return "Coach reminder"
            }
            if identifier.hasPrefix("thescale.fitness-trigger.") {
                return "Watch signal"
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
    /// Day ink. Night draws solid white on top of the glass so the glyph stays bright.
    var ink: Color = .primary

    @Environment(\.colorScheme) private var colorScheme

    private var glyph: Color {
        colorScheme == .dark ? .white : ink
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.01))
                    .frame(width: 40, height: 40)
                    .scaleGlassCircle()
                    .clipShape(Circle())
                    .frame(width: 40, height: 40)

                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(glyph)
                    .frame(width: 40, height: 40)
            }
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                if badgeCount > 0 {
                    Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.95), in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(badgeCount > 0 ? "Alerts, \(badgeCount) unread" : "Alerts")
    }
}
