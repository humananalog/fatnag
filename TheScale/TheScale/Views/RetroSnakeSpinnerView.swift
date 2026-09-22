import SwiftUI

/// Retro snake that actually plays while meal plan generates:
/// apples stay put until eaten; snake steers toward the apple and grows on eat.
struct RetroSnakeSpinnerView: View {
    var caption: String = "Hunting apples for your macros…"

    @State private var game = SnakeGameState(cols: 12, rows: 8)
    @State private var funnyIndex = 0

    private let ink = Color(red: 0.06, green: 0.18, blue: 0.08)
    private let appleColor = Color(red: 0.78, green: 0.12, blue: 0.14)
    private let grass = Color(red: 0.72, green: 0.88, blue: 0.70)
    private let tickSeconds: TimeInterval = 0.16

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: tickSeconds, paused: false)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / tickSeconds)
                canvas
                    .frame(width: 220, height: 148)
                    .background(grass.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ink.opacity(0.25), lineWidth: 2)
                    )
                    .onChange(of: step) { _, _ in
                        game.tick()
                        if game.justAte {
                            funnyIndex += 1
                        }
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

            Text("Score \(game.score)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(ink.opacity(0.55))
                .monospacedDigit()
        }
        .onAppear {
            if game.snake.isEmpty {
                game.reset()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating meal plan. Retro snake catching apples. Score \(game.score).")
    }

    private var funnyLine: String {
        let lines = [
            "Nom. That apple had protein goals.",
            "16/8 snake: no snacks before noon.",
            "High score unlocked: Lunch at noon, not Breakfast.",
            CoachPersona.thinkingSpinnerLine
        ]
        return lines[funnyIndex % lines.count]
    }

    private var canvas: some View {
        Canvas { context, size in
            let cellW = size.width / CGFloat(game.cols)
            let cellH = size.height / CGFloat(game.rows)

            // Static apple until eaten.
            let apple = game.apple
            let ax = CGFloat(apple.x) * cellW + cellW * 0.15
            let ay = CGFloat(apple.y) * cellH + cellH * 0.15
            context.fill(
                Path(ellipseIn: CGRect(x: ax, y: ay, width: cellW * 0.7, height: cellH * 0.7)),
                with: .color(appleColor)
            )

            for (offset, cell) in game.snake.enumerated() {
                let x = CGFloat(cell.x) * cellW + cellW * 0.12
                let y = CGFloat(cell.y) * cellH + cellH * 0.12
                let rect = CGRect(x: x, y: y, width: cellW * 0.76, height: cellH * 0.76)
                let alpha = offset == 0 ? 1.0 : max(0.35, 1.0 - Double(offset) * 0.12)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(ink.opacity(alpha))
                )
            }
        }
    }
}

/// Minimal grid snake: seek apple, eat, respawn apple on empty cell.
struct SnakeGameState {
    struct Cell: Hashable, Equatable {
        var x: Int
        var y: Int
    }

    let cols: Int
    let rows: Int
    var snake: [Cell] = []
    var apple: Cell = Cell(x: 0, y: 0)
    var direction: Cell = Cell(x: 1, y: 0)
    var score: Int = 0
    var justAte: Bool = false

    mutating func reset() {
        let midY = rows / 2
        snake = [
            Cell(x: 3, y: midY),
            Cell(x: 2, y: midY),
            Cell(x: 1, y: midY)
        ]
        direction = Cell(x: 1, y: 0)
        score = 0
        justAte = false
        placeApple()
    }

    mutating func tick() {
        justAte = false
        guard !snake.isEmpty else {
            reset()
            return
        }
        steerTowardApple()
        let head = snake[0]
        var next = Cell(x: head.x + direction.x, y: head.y + direction.y)

        // Wrap edges so the spinner never dies mid-generation.
        if next.x < 0 { next.x = cols - 1 }
        if next.x >= cols { next.x = 0 }
        if next.y < 0 { next.y = rows - 1 }
        if next.y >= rows { next.y = 0 }

        // Soft avoid self: pick alternate turn if about to bite body.
        if snake.contains(next) {
            let alternates = [
                Cell(x: direction.y, y: -direction.x),
                Cell(x: -direction.y, y: direction.x),
                Cell(x: -direction.x, y: -direction.y)
            ]
            for alt in alternates {
                var candidate = Cell(x: head.x + alt.x, y: head.y + alt.y)
                if candidate.x < 0 { candidate.x = cols - 1 }
                if candidate.x >= cols { candidate.x = 0 }
                if candidate.y < 0 { candidate.y = rows - 1 }
                if candidate.y >= rows { candidate.y = 0 }
                if !snake.contains(candidate) {
                    direction = alt
                    next = candidate
                    break
                }
            }
        }

        snake.insert(next, at: 0)
        if next == apple {
            score += 1
            justAte = true
            placeApple()
        } else if snake.count > 1 {
            snake.removeLast()
        }
    }

    private mutating func steerTowardApple() {
        let head = snake[0]
        let dx = apple.x - head.x
        let dy = apple.y - head.y
        // Prefer the larger axis gap; never reverse 180 in one step.
        let preferHorizontal = abs(dx) >= abs(dy)
        var desired = direction
        if preferHorizontal, dx != 0 {
            desired = Cell(x: dx > 0 ? 1 : -1, y: 0)
        } else if dy != 0 {
            desired = Cell(x: 0, y: dy > 0 ? 1 : -1)
        } else if dx != 0 {
            desired = Cell(x: dx > 0 ? 1 : -1, y: 0)
        }
        if desired.x == -direction.x, desired.y == -direction.y {
            return
        }
        direction = desired
    }

    private mutating func placeApple() {
        let occupied = Set(snake)
        var candidates: [Cell] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let cell = Cell(x: x, y: y)
                if !occupied.contains(cell) {
                    candidates.append(cell)
                }
            }
        }
        if let pick = candidates.randomElement() {
            apple = pick
        } else {
            // Board full: shrink slightly and place.
            if snake.count > 3 {
                snake = Array(snake.prefix(3))
            }
            apple = Cell(x: cols / 2, y: rows / 2)
        }
    }
}

#Preview {
    RetroSnakeSpinnerView()
        .padding()
}
