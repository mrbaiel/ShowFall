import SpriteKit

/// Снеговик или ёлка, стоящие на сугробе окна или на земле
final class Decor {
    enum Kind { case snowman, tree }

    let kind: Kind
    let node: SKNode
    /// nil = стоит на земле внизу экрана
    let windowID: Int?
    /// Для окна: X от левого края окна. Для земли: X на экране
    let localX: CGFloat
    let born: TimeInterval
    /// Разброс времени жизни, чтобы всё не исчезало одновременно
    let jitter: Double
    var lit = false
    var fallen = false

    init(kind: Kind, node: SKNode, windowID: Int?, localX: CGFloat, born: TimeInterval) {
        self.kind = kind
        self.node = node
        self.windowID = windowID
        self.localX = localX
        self.born = born
        self.jitter = Double.random(in: 0.8...1.2)
    }
}

/// Занятое место на кромке окна (чтобы фигуры не стояли друг в друге)
struct Slot {
    var x: CGFloat
    var kind: Decor.Kind
}

/// Что сейчас нарисовано на кромке окна (нужно для кликов)
struct CapGeom {
    var segs: [Segment]
    var topY: CGFloat
    var h: CGFloat
}
