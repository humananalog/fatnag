import Foundation
import Intents
import UIKit
import UserNotifications

/// Builds dual-presentation local notifications:
/// Watch / Lock Screen = short glance title + one-fact subtitle;
/// iPhone = richer body, attachment visual, optional Communication chrome.
enum ScaleNotificationContentFactory {
    struct Draft: Sendable {
        var kind: ScaleNotificationKind
        var title: String
        var subtitle: String
        var body: String
        /// Optional large attachment headline (defaults to title).
        var visualHeadline: String?
        var visualDetail: String?
        var userInfoExtras: [String: String] = [:]
        /// Optional per-fire relevance override (key moments).
        var relevanceScore: Double? = nil
    }

    static func make(_ draft: Draft) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        // Watch-first clamps: title is the only reliable wrist line.
        content.title = ScaleNotificationCopy.glanceSanitize(draft.title, max: 22)
        content.subtitle = ScaleNotificationCopy.clamp(draft.subtitle, max: 40)
        content.body = ScaleNotificationCopy.clamp(draft.body, max: 160)
        content.sound = draft.kind.interruptionLevel == .passive ? nil : .default
        content.categoryIdentifier = draft.kind.categoryId
        content.threadIdentifier = draft.kind.threadId
        content.interruptionLevel = draft.kind.interruptionLevel
        content.relevanceScore = draft.relevanceScore ?? draft.kind.relevanceScore

        var info: [AnyHashable: Any] = [
            ScaleNotificationUserInfoKey.destination: draft.kind.destination.rawValue,
            ScaleNotificationUserInfoKey.kind: draft.kind.rawValue,
            ScaleNotificationUserInfoKey.visualHint: draft.kind.visualStyle.rawValue,
            ScaleNotificationUserInfoKey.glanceTitle: content.title,
            ScaleNotificationUserInfoKey.phoneBody: content.body
        ]
        for (key, value) in draft.userInfoExtras {
            info[key] = value
        }
        content.userInfo = info
        if let dest = info[ScaleNotificationUserInfoKey.destination] as? String {
            content.targetContentIdentifier = dest
        } else {
            content.targetContentIdentifier = draft.kind.destination.rawValue
        }

        let headline = draft.visualHeadline ?? content.title
        let detail = draft.visualDetail ?? (content.subtitle.isEmpty ? content.body : content.subtitle)
        if let attachment = ScaleNotificationVisuals.makeAttachment(
            style: draft.kind.visualStyle,
            headline: ScaleNotificationCopy.clamp(headline, max: 24),
            detail: ScaleNotificationCopy.clamp(detail, max: 40)
        ) {
            content.attachments = [attachment]
        }

        if draft.kind.usesCommunicationStyle {
            let senderName = draft.kind == .nag ? "Nag" : "Coach"
            return applyCommunicationStyle(
                to: content,
                body: content.body,
                threadId: draft.kind.threadId,
                displayName: senderName
            ) ?? content
        }
        return content
    }

    static func make(_ moment: ScaleNotificationCopy.Moment) -> UNNotificationContent {
        make(moment.asDraft())
    }

    /// Dev / QA: immediate sample with full SOTA chrome.
    static func makeSample(
        profileName: String,
        currentKg: Double?,
        system: PreferredUnitSystem = PreferredUnitSystemStore.load()
    ) -> UNNotificationContent {
        make(ScaleNotificationCopy.sample(
            profileName: profileName,
            currentKg: currentKg,
            system: system
        ))
    }

    private static func applyCommunicationStyle(
        to content: UNMutableNotificationContent,
        body: String,
        threadId: String,
        displayName: String
    ) -> UNNotificationContent? {
        let senderId = displayName == "Nag" ? "nag" : "coach"
        let handle = INPersonHandle(value: "\(senderId)@fatnag.local", type: .unknown)
        let avatar = coachAvatarImage()
        let coach = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: displayName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: "fatnag.\(senderId)",
            isMe: false,
            suggestionType: .none
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: body,
            speakableGroupName: nil,
            conversationIdentifier: threadId,
            serviceName: "fatnag",
            sender: coach,
            attachments: nil
        )
        if let avatar {
            intent.setImage(avatar, forParameterNamed: \.sender)
        }

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
}
