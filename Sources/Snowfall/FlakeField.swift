import AppKit
import SpriteKit

/// Собственная физика снежинок.
/// На каждую действует гравитация и сопротивление воздуха (поэтому у хлопьев есть предельная
/// скорость падения), плюс покачивание, медленный ветер и отталкивание от курсора
/// только в небольшом радиусе. После толчка снежинка снова падает под действием гравитации.
final class FlakeField {
    struct Edge {
        var y: CGFloat
        var x0: CGFloat
        var x1: CGFloat
    }

    private final class Flake {
        let node = SKSpriteNode()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var depth: CGFloat = 1
        var swayAmp: CGFloat = 10
        var swayFreq: CGFloat = 1
        var swayPhase: CGFloat = 0
        var spin: CGFloat = 0
        var sticky = false
        var crystal = false
    }

    private let layer = SKNode()
    private let width: CGFloat
    private let height: CGFloat
    private var flakes: [Flake] = []
    private var sizeScale: CGFloat = 1
    private var speedScale: CGFloat = 1
    private var repelStrength: CGFloat = 0
    private(set) var repelRadius: CGFloat = 0

    /// Верхние кромки окон: часть снежинок «садится» на них
    var edges: [Edge] = []
    /// Положение курсора в координатах сцены (nil, если курсор далеко)
    var mouse: CGPoint?
    /// Земля: снежинки, долетевшие до неё, добавляют сугробу высоты
    weak var ground: GroundField?

    init(parent: SKNode, size: CGSize, zPosition: CGFloat) {
        width = size.width
        height = size.height
        layer.zPosition = zPosition
        parent.addChild(layer)
    }

    func configure(amount: CGFloat, size: CGFloat, speed: CGFloat,
                   repelCM: CGFloat, repelPower: CGFloat, ptPerCM: CGFloat) {
        sizeScale = size
        speedScale = speed
        repelRadius = repelCM * ptPerCM
        repelStrength = repelPower * 14

        let target = min(SnowTuning.maxFlakes, Int(amount * SnowTuning.flakesPerAmount))
        while flakes.count < target { spawn() }
        while flakes.count > target { flakes.removeLast().node.removeFromParent() }
        for f in flakes { restyle(f) }
    }

    // MARK: - Создание

    private func spawn() {
        let f = Flake()
        randomize(f)
        f.x = CGFloat.random(in: 0...width)
        f.y = CGFloat.random(in: 0...height)
        f.vy = -terminal(of: f)
        f.node.position = CGPoint(x: f.x, y: f.y)
        layer.addChild(f.node)
        flakes.append(f)
    }

    /// Новая внешность и повадки: большинство снежинок мелкие и «дальние»
    private func randomize(_ f: Flake) {
        let r = CGFloat.random(in: 0...1)
        f.depth = 0.3 + 0.7 * pow(r, 1.5)
        f.crystal = f.depth > 0.85 && Bool.random()
        f.node.texture = f.crystal ? SnowTextures.crystal : SnowTextures.soft
        f.node.alpha = 0.35 + 0.6 * f.depth
        f.node.zPosition = f.depth
        f.swayAmp = CGFloat.random(in: 6...18) * (0.6 + 0.4 * f.depth)
        f.swayFreq = CGFloat.random(in: 0.7...2.0)
        f.swayPhase = CGFloat.random(in: 0...(2 * .pi))
        f.spin = f.crystal ? CGFloat.random(in: -1.2...1.2) : 0
        f.sticky = CGFloat.random(in: 0...1) < 0.3
        restyle(f)
    }

    private func restyle(_ f: Flake) {
        let base: CGFloat = f.crystal ? 12 : 3.5 + 8.5 * f.depth
        let side = base * sizeScale
        f.node.size = CGSize(width: side, height: side)
    }

    private func terminal(of f: Flake) -> CGFloat {
        return (26 + 42 * f.depth) * speedScale
    }

    private func respawn(_ f: Flake) {
        randomize(f)
        f.x = CGFloat.random(in: 0...width)
        f.y = height + CGFloat.random(in: 10...80)
        f.vx = 0
        f.vy = -terminal(of: f)
        f.node.position = CGPoint(x: f.x, y: f.y)
    }

    // MARK: - Физика

    func update(dt: CGFloat, time: CGFloat) {
        // Сопротивление воздуха: скорость плавно возвращается к «установившемуся падению»
        let relax = min(1, 1.6 * dt)
        let wind = SnowTuning.windStrength * (0.6 * sin(time * 0.11) + 0.4 * sin(time * 0.29 + 1.3))

        let useRepel = repelRadius > 1 && repelStrength > 0 && mouse != nil
        let m = mouse ?? .zero
        let r2 = repelRadius * repelRadius

        for f in flakes {
            let targetVX = wind * (0.4 + 0.6 * f.depth) + f.swayAmp * sin(time * f.swayFreq + f.swayPhase)
            let targetVY = -terminal(of: f)
            f.vx += (targetVX - f.vx) * relax
            f.vy += (targetVY - f.vy) * relax

            // Толчок только внутри маленького круга вокруг курсора
            if useRepel {
                let dx = f.x - m.x
                let dy = f.y - m.y
                let d2 = dx * dx + dy * dy
                if d2 < r2 {
                    let d = max(d2.squareRoot(), 0.5)
                    let push = repelStrength * (1 - d / repelRadius)
                    f.vx += dx / d * push * dt
                    f.vy += dy / d * push * dt
                }
            }

            let prevY = f.y
            f.x += f.vx * dt
            f.y += f.vy * dt

            // Некоторые снежинки оседают на верхние кромки окон
            if f.sticky && !edges.isEmpty && f.y < prevY {
                var landed = false
                for e in edges where prevY >= e.y && f.y < e.y && f.x >= e.x0 && f.x <= e.x1 {
                    landed = true
                    break
                }
                if landed {
                    respawn(f)
                    continue
                }
            }

            // Земля: снежинка тает в сугробе и добавляет ему высоты
            if let g = ground {
                if f.y < g.surfaceY(at: f.x) {
                    g.land(x: f.x, volume: 0.3 + 0.5 * f.depth)
                    respawn(f)
                    continue
                }
            } else if f.y < -50 {
                respawn(f)
                continue
            }

            if f.x < -30 {
                f.x += width + 60
            } else if f.x > width + 30 {
                f.x -= width + 60
            }

            f.node.position = CGPoint(x: f.x, y: f.y)
            if f.spin != 0 { f.node.zRotation += f.spin * dt }
        }
    }
}
