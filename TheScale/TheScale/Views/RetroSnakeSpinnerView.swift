import SwiftUI

/// Funny retro snake catching apples while the meal plan generates.
struct RetroSnakeSpinnerView: View {
    var caption: String = "Hunting apples for your macros…"

    @State private var tick = 0
    private let cols = 12
    private let rows = 8
    private let ink = Color(red: 0.06, green: 0.18, blue: 0.08)
    private let apple = Color(red: 0.78, green: 0.12, blue: 0.14)
    private let grass = Color(red: 0.72, green: 0.88, blue: 0.70)

    private var path: [(Int, Int)] {
        // Closed loop path the snake head chases.
        var points: [(Int, Int)] = []
        for x in 1..<cols - 1 { points.append((x, 1)) }
        for y in 2..<rows - 1 { points.append((cols - 2, y)) }
        for x in stride(from: cols - 3, through: 1, by: -1) { points.append((x, rows - 2)) }
        for y in stride(from: rows - 3, through: 2, by: -1) { points.append((1, y)) }
        return points
    }

    private var appleCell: (Int, Int) {
        let apples = [(6, 3), (9, 4), (4, 5), (7, 2), (3, 4)]
        return apples[tick % apples.count]
    }

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 0.18, paused: false)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.18)
                canvas(step: step)
                    .frame(width: 220, height: 148)
                    .background(grass.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ink.opacity(0.25), lineWidth: 2)
                    )
                    .onChange(of: step) { _, newValue in
                        tick = newValue
                    }
            }

            Text(caption)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            Text(funnyLine)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating meal plan. Retro snake catching apples.")
    }

    private var funnyLine: String {
        let lines = [
            "Nom. That apple had protein goals.",
            "16/8 snake: no snacks before noon.",
            "High score unlocked: not inventing breakfast at 7am.",
            "Grok is thinking. Snake is snacking."
        ]
        return lines[tick % lines.count]
    }

    private func canvas(step: Int) -> some View {
        let loop = path
        guard !loop.isEmpty else { return AnyView(EmptyView()) }
        let headIndex = step % loop.count
        let length = 5
        let applePos = appleCell

        return AnyView(
            Canvas { context, size in
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height / CGFloat(rows)

                // Apple
                let ax = CGFloat(applePos.0) * cellW + cellW * 0.15
                let ay = CGFloat(applePos.1) * cellH + cellH * 0.15
                let appleRect = CGRect(x: ax, y: ay, width: cellW * 0.7, height: cellH * 0.7)
                context.fill(Path(ellipseIn: appleRect), with: .color(apple))

                // Snake body
                for offset in 0..<length {
                    let idx = (headIndex - offset + loop.count * 8) % loop.count
                    let cell = loop[idx]
                    let x = CGFloat(cell.0) * cellW + cellW * 0.12
                    let y = CGFloat(cell.1) * cellH + cellH * 0.12
                    let rect = CGRect(x: x, y: y, width: cellW * 0.76, height: cellH * 0.76)
                    let alpha = offset == 0 ? 1.0 : max(0.35, 1.0 - Double(offset) * 0.15)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(ink.opacity(alpha))
                    )
                }
            }
        )
    }
}

#Preview {
    RetroSnakeSpinnerView()
        .padding()
}
