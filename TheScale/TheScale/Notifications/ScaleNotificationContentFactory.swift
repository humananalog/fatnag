import Foundation
import Intents
import UIKit
import UserNotifications

/// Builds iOS 27-era local notification content: title/subtitle/body, threads,
/// categories, relevance, optional Communication style, and image attachments.
enum ScaleNotificationContentFactory {
    struct Draft: Sendable {
        var kind: ScaleNotificationKind
        var title: String
        var subtitle: String
        var body: String
        /// Optional large attachment headline (defaults to subtitle or title).
        var visualHeadline: String?
        var visualDetail: String?
        var userInfoExtras: [String: String] = [:]
    }

    static func make(_ draft: Draft) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = clamp(draft.title, max: 48)
        content.subtitle = clamp(draft.subtitle, max: 60)
        content.body = clamp(draft.body, max: 160)
        content.sound = draft.kind.interruptionLevel == .passive ? nil : .default
        content.categoryIdentifier = draft.kind.categoryId
        content.threadIdentifier = draft.kind.threadId
        content.interruptionLevel = draft.kind.interruptionLevel
        content.relevanceScore = draft.kind.relevanceScore
        content.targetContentIdentifier = draft.kind.destination.rawValue

        var info: [AnyHashable: Any] = [
            ScaleNotificationUserInfoKey.destination: draft.kind.destination.rawValue,
            ScaleNotificationUserInfoKey.kind: draft.kind.rawValue,
            ScaleNotificationUserInfoKey.visualHint: draft.kind.visualStyle.rawValue
        ]
        for (key, value) in draft.userInfoExtras {
            info[key] = value
        }
        content.userInfo = info

        let headline = draft.visualHeadline ?? (draft.subtitle.isEmpty ? draft.title : draft.subtitle)
        let detail = draft.visualDetail ?? draft.body
        if let attachment = ScaleNotificationVisuals.makeAttachment(
            style: draft.kind.visualStyle,
            headline: clamp(headline, max: 28),
            detail: clamp(detail, max: 42)
        ) {
            content.attachments = [attachment]
        }

        if draft.kind.usesCommunicationStyle {
            return applyCommunicationStyle(to: content, body: content.body, threadId: draft.kind.threadId)
                ?? content
        }
        return content
    }

    /// Dev / QA: immediate sample with full SOTA chrome.
    static func makeSample(profileName: String, currentKg: Double?) -> UNNotificationContent {
        let name = profileName.isEmpty ? "Hey" : profileName
        let kgLine = currentKg.map { String(format: "%.1f kg on file" , $0) } ?? "No Health weight yet"
        return make(
            Draft(
                kind: .sample,
                title: "\(name): sample ping",
                subtitle: kgLine,
                body: "SOTA local banner with Coach chrome, actions, and a visual. Tap Open Coach.",
                visualHeadline: currentKg.map { String(format: "%.1f kg", $0) } ?? "Coach",
                visualDetail: "Sample · The Scale"
            )
        )
    }

    private static func applyCommunicationStyle(
        to content: UNMutableNotificationContent,
        body: String,
        threadId: String
    ) -> UNNotificationContent? {
        let handle = INPersonHandle(value: "coach@thescale.local", type: .unknown)
        let avatar = coachAvatarImage()
        let coach = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: "Coach",
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: "thescale.coach",
            isMe: false,
            suggestionType: .none
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: body,
            speakableGroupName: nil,
            conversationIdentifier: threadId,
            serviceName: "The Scale",
            sender: coach,
            attachments: nil
        )
        if let avatar {
            intent.setImage(avatar, forParameterNamed: \.sender)
        }

        // Prefer attributed message context on modern iOS; fall back to intent provider.
        do {
            let attributed = NSAttributedString(string: body)
            let context = UNNotificationAttributedMessageContext(
                sendMessageIntent: intent,
                attributedContent: attributed
            )
            return try content.updating(from: context)
        } catch {
            do {
                return try content.updating(from: intent)
            } catch {
                return nil
            }
        }
    }

    private static func coachAvatarImage() -> INImage? {
        if let ui = UIImage(named: "BrandMark"), let data = ui.pngData() {
            return INImage(imageData: data)
        }
        return INImage(named: "BrandMark")
    }

    private static func clamp(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max - 1)
        return String(trimmed[..<idx]) + "…"
    }
}
