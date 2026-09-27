import Foundation
import UIKit
import UserNotifications

/// Renders small PNG attachments for Lock Screen / expanded notification visuals.
enum ScaleNotificationVisuals {
    /// Writes a temp PNG and returns a `UNNotificationAttachment`, or nil on failure.
    static func makeAttachment(
        style: ScaleNotificationVisualStyle,
        headline: String,
        detail: String?
    ) -> UNNotificationAttachment? {
        guard let data = renderPNG(style: style, headline: headline, detail: detail) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thescale-notif-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "thescale.visual.\(style.rawValue)",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    static func renderPNG(
        style: ScaleNotificationVisualStyle,
        headline: String,
        detail: String?
    ) -> Data? {
        let size = CGSize(width: 390, height: 168)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = gradient(for: style)
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: space,
                colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Soft vignette for Lock Screen richness (iPhone); Watch ignores attachment.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 48, width: size.width, height: 48))

            drawGlyph(style: style, in: CGRect(x: 20, y: 30, width: 58, height: 58), context: cg)

            let title = headline as NSString
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            title.draw(at: CGPoint(x: 92, y: 32), withAttributes: titleAttrs)

            if let detail, !detail.isEmpty {
                let sub = detail as NSString
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9)
                ]
                sub.draw(at: CGPoint(x: 92, y: 74), withAttributes: subAttrs)
            }

            let brandFat = "fat" as NSString
            let brandNag = "nag" as NSString
            let fatAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let nagAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let fatSize = brandFat.size(withAttributes: fatAttrs)
            brandFat.draw(at: CGPoint(x: 90, y: 118), withAttributes: fatAttrs)
            brandNag.draw(at: CGPoint(x: 90 + fatSize.width, y: 118), withAttributes: nagAttrs)
        }
        return image.pngData()
    }

    private static func gradient(for style: ScaleNotificationVisualStyle) -> (UIColor, UIColor) {
        switch style {
        case .trendUp:
            return (
                UIColor(red: 0.55, green: 0.18, blue: 0.16, alpha: 1),
                UIColor(red: 0.22, green: 0.10, blue: 0.12, alpha: 1)
            )
        case .goal:
            return (
                UIColor(red: 0.12, green: 0.32, blue: 0.28, alpha: 1),
                UIColor(red: 0.08, green: 0.16, blue: 0.18, alpha: 1)
            )
        case .heart:
            return (
                UIColor(red: 0.45, green: 0.14, blue: 0.28, alpha: 1),
                UIColor(red: 0.18, green: 0.08, blue: 0.16, alpha: 1)
            )
        case .watch:
            return (
                UIColor(red: 0.18, green: 0.22, blue: 0.34, alpha: 1),
                UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1)
            )
        case .pulse, .coach, .sample:
            return (
                UIColor(red: 0.14, green: 0.18, blue: 0.24, alpha: 1),
                UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
            )
        }
    }

    private static func drawGlyph(
        style: ScaleNotificationVisualStyle,
        in rect: CGRect,
        context: CGContext
    ) {
        let symbolName: String = {
            switch style {
            case .coach, .sample: return "sparkles"
            case .trendUp: return "arrow.up.right"
            case .goal: return "flag.checkered"
            case .watch: return "applewatch"
            case .heart: return "heart.fill"
            case .pulse: return "waveform.path.ecg"
            }
        }()
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        guard let image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        else { return }
        let imgSize = image.size
        let origin = CGPoint(
            x: rect.midX - imgSize.width / 2,
            y: rect.midY - imgSize.height / 2
        )
        image.draw(at: origin)
        _ = context
    }
}
