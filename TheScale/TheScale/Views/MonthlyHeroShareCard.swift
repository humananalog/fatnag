import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// WhatsApp Status default, and the portrait that still fits an iPhone.
/// 360×640 pt at 3× is 1080×1920, exactly 9:16.
enum MonthlyHeroShareCanvas {
    static let pointSize = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3
    static let pixelSize = CGSize(width: 1080, height: 1920)
}

/// JPEG the system share sheet can hand to WhatsApp, Messages, and Photos.
struct MonthlyHeroShareImage: Transferable, Sendable, Equatable {
    var jpeg: Data
    var subject: String
    var message: String
    var filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            item.jpeg
        }
        .suggestedFileName { $0.filename }
    }
}

enum MonthlyHeroShareCopy {
    /// Same final number the card counts up to. Grams and ounces sit tight (`−400g`).
    static func delta(facts: MonthlyHeroFacts, units: PreferredUnitSystem) -> String {
        guard let kg = facts.heroNumberKg else { return "—" }
        if facts.heroNumberIsDelta {
            if facts.direction == .stable {
                if abs(kg) < 1, !units.usesImperialMass {
                    return "±\(Int((abs(kg) * 1000).rounded()))g"
                }
                let value = UnitFormat.mass(fromKg: abs(kg), system: units)
                return "±\(String(format: "%.1f", value)) \(units.massLabel)"
            }
            let sign = facts.direction == .gain ? "+" : "−"
            if abs(kg) < 1, !units.usesImperialMass {
                return "\(sign)\(Int((abs(kg) * 1000).rounded()))g"
            }
            let value = UnitFormat.mass(fromKg: abs(kg), system: units)
            return "\(sign)\(String(format: "%.1f", value)) \(units.massLabel)"
        }
        let value = UnitFormat.mass(fromKg: kg, system: units)
        return "\(String(format: "%.1f", value)) \(units.massLabel)"
    }

    static func endpoint(_ kg: Double, units: PreferredUnitSystem) -> String {
        UnitFormat.massString(kg, system: units, fractionDigits: 1)
    }

    /// Uppercase month, only when the festival line does not already say it.
    static func monthKicker(monthName: String, festivalTitle: String) -> String? {
        let month = monthName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard month.count >= 3 else { return nil }
        if festivalTitle.range(of: month, options: .caseInsensitive) != nil { return nil }
        return month.uppercased()
    }

    /// Insight for the poster. The hero already showed the unit, the delta, and the month.
    static func posterInsight(raw: String, facts: MonthlyHeroFacts, units: PreferredUnitSystem) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = text.firstIndex(of: ","), text.distance(from: text.startIndex, to: comma) <= 16 {
            let head = text[..<comma]
            if head.split(separator: " ").count == 1 {
                text = String(text[text.index(after: comma)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        text = text.replacingOccurrences(of: "This month:", with: "", options: .caseInsensitive)
        if monthKicker(monthName: facts.monthName, festivalTitle: facts.festivalTitle) == nil,
           facts.monthName.count >= 3 {
            text = text.replacingOccurrences(of: facts.monthName, with: "", options: .caseInsensitive)
        }
        if let phrase = facts.unit?.phrase, !phrase.isEmpty {
            text = text.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        if let kg = facts.deltaKg {
            let signed = UnitFormat.massDeltaString(kg, system: units)
            text = text.replacingOccurrences(of: signed, with: "")
            let bare = UnitFormat.massString(abs(kg), system: units, fractionDigits: 2)
            text = text.replacingOccurrences(of: bare, with: "")
        }
        text = text.replacingOccurrences(
            of: #"[−+\-±]?\d+(?:[.,]\d+)?\s?(?:kg|lb|lbs|oz|g)\b"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\s*\([^)]*(?:kg|lb|lbs|oz|g)[^)]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*\(\s*\)"#, with: "", options: .regularExpression)

        let sentences = text
            .replacingOccurrences(of: "!", with: ".")
            .replacingOccurrences(of: "?", with: ".")
            .components(separatedBy: ".")
            .map { tidyPosterSentence($0) }
            .filter { $0.split(separator: " ").count >= 2 }

        guard !sentences.isEmpty else { return "" }
        return sentences.joined(separator: ". ") + "."
    }

    private static func tidyPosterSentence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let glue = #"(?i)^(down|up|about|lighter by|since last month|since early|versus a typical|versus about a month ago)\b[, ]*"#
        while let range = text.range(of: glue, options: .regularExpression) {
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.lowercased().hasPrefix("is ") {
            text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,—-"))
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }

    /// The action is the instruction. The poster is already the month.
    static func posterAction(_ action: String) -> String {
        var text = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "this month:"
        if text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}

enum MonthlyHeroShareRenderer {
    @MainActor
    static func render(
        facts: MonthlyHeroFacts,
        insight: String,
        universe: ScalePaletteUniverse,
        units: PreferredUnitSystem
    ) -> MonthlyHeroShareImage? {
        let poster = MonthlyHeroSharePoster(
            facts: facts,
            insight: insight,
            universe: universe,
            units: units
        )
        .frame(width: MonthlyHeroShareCanvas.pointSize.width, height: MonthlyHeroShareCanvas.pointSize.height)

        let renderer = ImageRenderer(content: poster)
        renderer.scale = MonthlyHeroShareCanvas.scale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(
            width: MonthlyHeroShareCanvas.pointSize.width,
            height: MonthlyHeroShareCanvas.pointSize.height
        )
        guard let image = renderer.uiImage, let jpeg = srgbJPEG(from: image) else { return nil }

        let delta = MonthlyHeroShareCopy.delta(facts: facts, units: units)
        let unitLine = facts.unit?.phrase
        var message = "\(facts.festivalTitle) · \(facts.bigWord) \(delta)"
        if let unitLine, !unitLine.isEmpty {
            message += " · \(unitLine)"
        }
        let slug = facts.monthKey.filter { $0.isNumber || $0 == "-" }
        return MonthlyHeroShareImage(
            jpeg: jpeg,
            subject: facts.festivalTitle,
            message: message,
            filename: "fatnag-\(slug.isEmpty ? "month" : slug).jpg"
        )
    }

    /// WhatsApp re-encodes whatever it receives. sRGB JPEG avoids the P3 / PNG-alpha surprises.
    private static func srgbJPEG(from image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        let canvas = UIGraphicsImageRenderer(size: image.size, format: format)
        let flat = canvas.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return flat.jpegData(compressionQuality: 0.92)
    }
}

/// One still of the monthly story. No chrome, no buttons. Safe margins for WhatsApp Status.
private struct MonthlyHeroSharePoster: View {
    var facts: MonthlyHeroFacts
    var insight: String
    var universe: ScalePaletteUniverse
    var units: PreferredUnitSystem

    private var style: MonthlyHeroPosterStyle {
        MonthlyHeroPosterStyle.make(universe: universe, month: facts.month, direction: facts.direction)
    }

    var body: some View {
        let accent = style.accent
        let delta = MonthlyHeroShareCopy.delta(facts: facts, units: units)
        let hero = facts.unit?.emoji ?? facts.burst.first ?? facts.festivalEmoji
        let seasonMark = facts.festivalEmoji == hero ? nil : facts.festivalEmoji
        ZStack {
            LinearGradient(
                colors: [style.voidTop, style.voidMid, style.voidBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(style.primary.opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 42)
                .offset(x: -70, y: -210)
            Circle()
                .fill(style.secondary.opacity(0.42))
                .frame(width: 240, height: 240)
                .blur(radius: 48)
                .offset(x: 100, y: 180)

            VStack(alignment: .leading, spacing: 0) {
                masthead(accent: accent, seasonMark: seasonMark)

                Spacer(minLength: 20)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(facts.bigWord)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(style.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(delta)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }

                Capsule()
                    .fill(accent)
                    .frame(width: 36, height: 3)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.30))
                            .frame(width: 150, height: 150)
                            .blur(radius: 20)
                        Text(hero)
                            .font(.system(size: 96))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    if let phrase = facts.unit?.phrase {
                        Text(phrase)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(style.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                }

                Spacer(minLength: 18)

                storyBand(accent: accent, insight: insight)
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 48)
        }
        .frame(width: MonthlyHeroShareCanvas.pointSize.width, height: MonthlyHeroShareCanvas.pointSize.height)
        .clipped()
        .preferredColorScheme(.dark)
    }

    private func masthead(accent: Color, seasonMark: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FatnagWordmark(size: 15, color: style.ink.opacity(0.88), tracking: -0.4)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let kicker = MonthlyHeroShareCopy.monthKicker(
                        monthName: facts.monthName,
                        festivalTitle: facts.festivalTitle
                    ) {
                        Text(kicker)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(accent)
                    }
                    Text(facts.festivalTitle)
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(style.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                if let seasonMark {
                    Text(seasonMark)
                        .font(.system(size: 36))
                }
            }
        }
    }

    private func storyBand(accent: Color, insight: String) -> some View {
        let line = MonthlyHeroShareCopy.posterInsight(raw: insight, facts: facts, units: units)
        let action = MonthlyHeroShareCopy.posterAction(facts.monthlyAction)
        return VStack(alignment: .leading, spacing: 14) {
            if facts.sparkline.count >= 2 {
                shareSparkline(accent: accent)
            }
            if !line.isEmpty {
                Text(line)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(style.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !action.isEmpty {
                Text(action)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareSparkline(accent: Color) -> some View {
        let start = facts.sparkline.first.map { MonthlyHeroShareCopy.endpoint($0, units: units) } ?? ""
        let end = facts.sparkline.last.map { MonthlyHeroShareCopy.endpoint($0, units: units) } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(start)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.mist)
                Spacer(minLength: 8)
                Text(end)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            MonthlySparkline(values: facts.sparkline)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(height: 72)
                .background(alignment: .bottom) {
                    Capsule()
                        .fill(accent.opacity(0.28))
                        .frame(height: 2)
                }
        }
    }
}

private struct MonthlyHeroPosterStyle {
    var ink: Color
    var mist: Color
    var accent: Color
    var voidTop: Color
    var voidMid: Color
    var voidBottom: Color
    var primary: Color
    var secondary: Color

    static func make(universe: ScalePaletteUniverse, month: Int, direction: MonthlyDirection) -> MonthlyHeroPosterStyle {
        let wash = washColors(universe: universe, month: month)
        let accent: Color
        switch universe {
        case .glacierForge:
            switch direction {
            case .loss: accent = Color(red: 0.45, green: 0.93, blue: 0.84)
            case .gain: accent = Color(red: 0.98, green: 0.62, blue: 0.42)
            case .stable, .unknown: accent = Color(red: 0.72, green: 0.84, blue: 0.96)
            }
        case .bloomCopper:
            switch direction {
            case .loss: accent = Color(red: 0.98, green: 0.78, blue: 0.55)
            case .gain: accent = Color(red: 0.96, green: 0.48, blue: 0.52)
            case .stable, .unknown: accent = Color(red: 0.98, green: 0.82, blue: 0.74)
            }
        }
        let mist = universe == .bloomCopper
            ? Color(red: 0.86, green: 0.74, blue: 0.70)
            : Color(red: 0.70, green: 0.78, blue: 0.82)
        return MonthlyHeroPosterStyle(
            ink: Color(red: 0.97, green: 0.95, blue: 0.92),
            mist: mist,
            accent: accent,
            voidTop: wash.0,
            voidMid: wash.1,
            voidBottom: wash.2,
            primary: wash.3,
            secondary: wash.4
        )
    }

    private static func washColors(universe: ScalePaletteUniverse, month: Int) -> (Color, Color, Color, Color, Color) {
        switch universe {
        case .glacierForge:
            switch month {
            case 12, 1, 2:
                return (
                    Color(red: 0.05, green: 0.08, blue: 0.14),
                    Color(red: 0.07, green: 0.12, blue: 0.18),
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.45, green: 0.78, blue: 0.95),
                    Color(red: 0.70, green: 0.82, blue: 0.95)
                )
            case 6, 7, 8:
                return (
                    Color(red: 0.04, green: 0.10, blue: 0.12),
                    Color(red: 0.06, green: 0.16, blue: 0.16),
                    Color(red: 0.03, green: 0.07, blue: 0.09),
                    Color(red: 0.20, green: 0.82, blue: 0.72),
                    Color(red: 0.95, green: 0.78, blue: 0.28)
                )
            case 9, 10, 11:
                return (
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.10, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.95, green: 0.55, blue: 0.22),
                    Color(red: 0.25, green: 0.62, blue: 0.70)
                )
            default:
                return (
                    Color(red: 0.05, green: 0.10, blue: 0.12),
                    Color(red: 0.07, green: 0.14, blue: 0.14),
                    Color(red: 0.04, green: 0.07, blue: 0.09),
                    Color(red: 0.35, green: 0.82, blue: 0.62),
                    Color(red: 0.45, green: 0.75, blue: 0.90)
                )
            }
        case .bloomCopper:
            switch month {
            case 12, 1, 2:
                return (
                    Color(red: 0.12, green: 0.07, blue: 0.10),
                    Color(red: 0.16, green: 0.08, blue: 0.12),
                    Color(red: 0.08, green: 0.04, blue: 0.07),
                    Color(red: 0.95, green: 0.72, blue: 0.78),
                    Color(red: 0.78, green: 0.84, blue: 0.95)
                )
            case 6, 7, 8:
                return (
                    Color(red: 0.14, green: 0.06, blue: 0.07),
                    Color(red: 0.18, green: 0.08, blue: 0.08),
                    Color(red: 0.08, green: 0.04, blue: 0.05),
                    Color(red: 0.98, green: 0.55, blue: 0.38),
                    Color(red: 0.98, green: 0.78, blue: 0.42)
                )
            case 9, 10, 11:
                return (
                    Color(red: 0.12, green: 0.06, blue: 0.07),
                    Color(red: 0.16, green: 0.07, blue: 0.08),
                    Color(red: 0.07, green: 0.04, blue: 0.05),
                    Color(red: 0.92, green: 0.48, blue: 0.32),
                    Color(red: 0.82, green: 0.55, blue: 0.38)
                )
            default:
                return (
                    Color(red: 0.12, green: 0.07, blue: 0.09),
                    Color(red: 0.16, green: 0.08, blue: 0.11),
                    Color(red: 0.08, green: 0.04, blue: 0.07),
                    Color(red: 0.96, green: 0.62, blue: 0.70),
                    Color(red: 0.92, green: 0.74, blue: 0.48)
                )
            }
        }
    }
}
