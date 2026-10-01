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

            // Extra black wash so white type stays high-contrast on Lock Screen / banners.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 52, width: size.width, height: 52))

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
                    .foregroundColor: UIColor.white
                ]
                sub.draw(at: CGPoint(x: 92, y: 74), withAttributes: subAttrs)
            }

            let brandFat = "fat" as NSString
            let brandNag = "nag" as NSString
            let fatAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let nagAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let fatSize = brandFat.size(withAttributes: fatAttrs)
            brandFat.draw(at: CGPoint(x: 90, y: 118), withAttributes: fatAttrs)
            brandNag.draw(at: CGPoint(x: 90 + fatSize.width, y: 118), withAttributes: nagAttrs)
        }
        return image.pngData()
    }

    /// Near-black bases so white type reads as white-over-black on every style.
    private static func gradient(for style: ScaleNotificationVisualStyle) -> (UIColor, UIColor) {
        let black = UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        switch style {
        case .trendUp:
            return (UIColor(red: 0.18, green: 0.04, blue: 0.05, alpha: 1), black)
        case .goal:
            return (UIColor(red: 0.04, green: 0.12, blue: 0.10, alpha: 1), black)
        case .heart:
            return (UIColor(red: 0.14, green: 0.03, blue: 0.08, alpha: 1), black)
        case .watch:
            return (UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1), black)
        case .pulse, .coach, .sample:
            return (UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1), black)
        case .nag:
            return (UIColor(red: 0.16, green: 0.08, blue: 0.02, alpha: 1), black)
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
            case .nag: return "megaphone.fill"
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
