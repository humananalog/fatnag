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
                if abs(kg) < 1, units == .metric {
                    return "±\(Int((abs(kg) * 1000).rounded()))g"
                }
                let value = UnitFormat.mass(fromKg: abs(kg), system: units)
                return "±\(String(format: "%.1f", value)) \(units.massLabel)"
            }
            let sign = facts.direction == .gain ? "+" : "−"
            if abs(kg) < 1, units == .metric {
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
        var message = "\(facts.monthName): \(facts.bigWord) \(delta)"
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
                HStack(alignment: .firstTextBaseline) {
                    Text("\(facts.monthName.uppercased())  \(facts.festivalEmoji)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    FatnagWordmark(size: 15, color: style.ink.opacity(0.9), tracking: -0.4)
                }

                Text(facts.festivalTitle)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(style.ink.opacity(0.78))
                    .lineLimit(1)
                    .padding(.top, 6)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(facts.bigWord)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(style.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(delta)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }
                .padding(.top, 16)

                Spacer(minLength: 8)

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.22))
                            .frame(width: 150, height: 150)
                            .blur(radius: 16)
                        Text(hero)
                            .font(.system(size: 92))
                    }
                    .frame(maxWidth: .infinity)
                    if !facts.burst.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(Array(facts.burst.prefix(4).enumerated()), id: \.offset) { _, emoji in
                                Text(emoji)
                                    .font(.system(size: 22))
                            }
                        }
                    }
                    if let phrase = facts.unit?.phrase {
                        Text(phrase)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(style.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Spacer(minLength: 8)

                if facts.sparkline.count >= 2 {
                    shareSparkline(accent: accent)
                        .padding(.top, 4)
                }

                Text(insight)
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(style.ink)
                    .lineLimit(4)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Text(facts.monthlyAction)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                    )
                    .padding(.top, 12)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 26)
            .padding(.top, 58)
            .padding(.bottom, 64)
        }
        .frame(width: MonthlyHeroShareCanvas.pointSize.width, height: MonthlyHeroShareCanvas.pointSize.height)
        .clipped()
        .preferredColorScheme(.dark)
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
