import AppKit
import SpriteKit

/// Сугроб внизу экрана (на верхней кромке Dock) и игрушечные экскаваторы, которые его разгребают.
/// Сугроб это массив высот по столбцам: снежинки добавляют снег, экскаватор толкает его вперёд.
final class GroundField {
    final class Excavator {
        let node: SKSpriteNode
        var x: CGFloat
        var dir: CGFloat
        var turnDistance: CGFloat
        var travelled: CGFloat = 0
        let born: TimeInterval
        var leaving = false

        init(x: CGFloat, dir: CGFloat, born: TimeInterval) {
            self.x = x
            self.dir = dir
            self.born = born
            self.turnDistance = CGFloat.random(in: 200...520)
            self.node = SKSpriteNode(texture: SnowTextures.excavator)
            node.size = CGSize(width: 60, height: 40)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = 14
        }
    }

    static let colW: CGFloat = 6

    private let width: CGFloat
    private let baseY: CGFloat
    private let cols: Int
    private var h: [CGFloat]
    private let shape = SKShapeNode()
    private let layer = SKNode()
    private var dirty = true
    private var tickCount = 0

    private var maxHeight: CGFloat = 18
    private var excavatorMax = 1
    private var excavatorLife: TimeInterval = 90
    private var enabled = true
    private var nextSpawn: TimeInterval = 0

    private(set) var excavators: [Excavator] = []

    /// Растёт при каждой перестройке сугроба: по нему 3D-модель понимает, что пора обновиться
    private(set) var revision = 0
    private(set) var peak: CGFloat = 0
    var isEnabled: Bool { return enabled }
    /// Включён 3D-режим: плоские картинки сугроба и экскаваторов прячем
    var hideVisuals = false {
        didSet {
            layer.isHidden = hideVisuals
            dirty = true
        }
    }

    private let bladeOffset: CGFloat = 29   // отвал впереди центра экскаватора
    private let bodyHalf: CGFloat = 24
    private let keep: CGFloat = 0.8         // сколько снега остаётся на расчищенной полосе

    init(parent: SKNode, width: CGFloat, baseY: CGFloat) {
        self.width = width
        self.baseY = baseY
        self.cols = Int(width / GroundField.colW) + 2
        self.h = [CGFloat](repeating: 0, count: cols)

        shape.fillColor = NSColor(white: 0.98, alpha: 0.98)
        shape.strokeColor = NSColor(calibratedRed: 0.70, green: 0.79, blue: 0.90, alpha: 0.9)
        shape.lineWidth = 1
        shape.zPosition = 9
        shape.isHidden = true
        layer.zPosition = 14
        parent.addChild(shape)
        parent.addChild(layer)
        nextSpawn = ProcessInfo.processInfo.systemUptime + 12
    }

    func configure(maxHeight: CGFloat, excavatorMax: Int, excavatorLife: TimeInterval, enabled: Bool) {
        self.maxHeight = maxHeight
        self.excavatorMax = excavatorMax
        self.excavatorLife = excavatorLife
        if self.enabled && !enabled { clear() }
        self.enabled = enabled
        for i in h.indices { h[i] = min(h[i], maxHeight) }
        dirty = true
    }

    func clear() {
        for i in h.indices { h[i] = 0 }
        excavators.forEach { $0.node.removeFromParent() }
        excavators.removeAll()
        dirty = true
    }

    // MARK: - Высота

    /// Копия высот по столбцам (для 3D-модели)
    func snapshot() -> [CGFloat] {
        return h
    }

    private func idx(_ x: CGFloat) -> Int {
        return min(max(Int(x / GroundField.colW), 0), cols - 1)
    }

    func height(at x: CGFloat) -> CGFloat {
        let f = min(max(x / GroundField.colW, 0), CGFloat(cols - 1) - 0.001)
        let i = Int(f)
        let t = f - CGFloat(i)
        return h[i] * (1 - t) + h[i + 1] * t
    }

    func surfaceY(at x: CGFloat) -> CGFloat {
        return baseY + (enabled ? height(at: x) : 0)
    }

    private func meanHeight() -> CGFloat {
        var sum: CGFloat = 0
        for v in h { sum += v }
        return sum / CGFloat(h.count)
    }

    /// Снежинка упала: добавляем снег в столбец и по чуть-чуть в соседние
    func land(x: CGFloat, volume: CGFloat) {
        let i = idx(x)
        add(i, volume * 0.5)
        if i > 0 { add(i - 1, volume * 0.25) }
        if i < cols - 1 { add(i + 1, volume * 0.25) }
        dirty = true
    }

    private func add(_ i: Int, _ v: CGFloat) {
        h[i] = min(maxHeight, h[i] + v)
    }

    /// Клик по сугробу: снег разлетается. Возвращает, сколько его улетело
    func scatter(at x: CGFloat, radius: CGFloat, fraction: CGFloat) -> CGFloat {
        var removed: CGFloat = 0
        let c0 = idx(x - radius)
        let c1 = idx(x + radius)
        for c in c0...c1 {
            let cx = CGFloat(c) * GroundField.colW
            let falloff = max(0, 1 - abs(cx - x) / radius)
            let take = h[c] * fraction * falloff
            h[c] -= take
            removed += take
        }
        dirty = true
        return removed
    }

    // MARK: - Кадр

    func update(dt: CGFloat, now: TimeInterval) {
        guard enabled else {
            shape.isHidden = true
            return
        }
        manageExcavators(dt: dt, now: now)
        settle()
        tickCount += 1
        if dirty && tickCount % 2 == 0 { rebuild() }
    }

    /// Снег не держит слишком крутых склонов: излишки сползают вниз
    private func settle() {
        let maxDiff: CGFloat = 1.6
        var changed = false
        for _ in 0..<2 {
            for i in 0..<(cols - 1) {
                let d = h[i] - h[i + 1]
                if d > maxDiff {
                    let t = (d - maxDiff) * 0.2
                    h[i] -= t
                    h[i + 1] += t
                    if t > 0.004 { changed = true }
                } else if d < -maxDiff {
                    let t = (-d - maxDiff) * 0.2
                    h[i] += t
                    h[i + 1] -= t
                    if t > 0.004 { changed = true }
                }
            }
        }
        if changed { dirty = true }
    }

    private func rebuild() {
        dirty = false
        revision += 1

        var top: CGFloat = 0
        for v in h { top = max(top, v) }
        peak = top

        if hideVisuals {
            shape.isHidden = true
            return
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: baseY - 4))
        for i in 0..<cols {
            path.addLine(to: CGPoint(x: CGFloat(i) * GroundField.colW, y: baseY + h[i]))
        }
        path.addLine(to: CGPoint(x: CGFloat(cols - 1) * GroundField.colW, y: baseY - 4))
        path.closeSubpath()
        shape.path = path
        shape.isHidden = !enabled || top < 0.6
    }

    // MARK: - Экскаваторы

    private func manageExcavators(dt: CGFloat, now: TimeInterval) {
        let working = excavators.filter { !$0.leaving }

        if working.count < excavatorMax && now >= nextSpawn && meanHeight() > SnowTuning.excavatorMinSnow {
            nextSpawn = now + Double.random(in: 8...20)
            spawnExcavator(now: now)
        }

        // Если лимит уменьшили, самые старые уезжают
        if working.count > excavatorMax {
            let extra = working.sorted { $0.born < $1.born }.prefix(working.count - excavatorMax)
            for ex in extra { sendAway(ex) }
        }

        for ex in excavators { step(ex, dt: dt, now: now) }

        excavators.removeAll { ex in
            if ex.leaving && (ex.x < -80 || ex.x > width + 80) {
                ex.node.removeFromParent()
                return true
            }
            return false
        }
    }

    private func spawnExcavator(now: TimeInterval) {
        let fromLeft = Bool.random()
        let ex = Excavator(x: fromLeft ? -40 : width + 40, dir: fromLeft ? 1 : -1, born: now)
        layer.addChild(ex.node)
        excavators.append(ex)
    }

    private func sendAway(_ ex: Excavator) {
        ex.leaving = true
        ex.dir = ex.x < width / 2 ? -1 : 1
    }

    private func step(_ ex: Excavator, dt: CGFloat, now: TimeInterval) {
        if !ex.leaving && excavatorLife.isFinite && now - ex.born > excavatorLife {
            sendAway(ex)
        }

        let speed: CGFloat = ex.leaving ? 70 : 36
        let dx = ex.dir * speed * dt
        plow(ex, dx: dx)
        ex.x += dx
        ex.travelled += abs(dx)

        if !ex.leaving {
            let hitEdge = (ex.x < 30 && ex.dir < 0) || (ex.x > width - 30 && ex.dir > 0)
            if ex.travelled > ex.turnDistance || hitEdge {
                ex.dir = -ex.dir
                ex.travelled = 0
                ex.turnDistance = CGFloat.random(in: 200...520)
            }
        }

        let y = surfaceY(at: ex.x) + 0.5
        let a = surfaceY(at: ex.x - 16)
        let b = surfaceY(at: ex.x + 16)
        let tilt = min(max(atan2(b - a, 32), -0.4), 0.4)
        let bob: CGFloat = abs(dx) > 0 ? sin(CGFloat(now) * 22) * 0.4 : 0
        ex.node.position = CGPoint(x: ex.x, y: y + bob)
        ex.node.zRotation = tilt
        ex.node.xScale = ex.dir
    }

    /// Отвал расчищает полосу под экскаватором, а снег толкает перед собой
    private func plow(_ ex: Excavator, dx: CGFloat) {
        let bladeNew = ex.x + dx + ex.dir * bladeOffset
        let lo = min(ex.x - bodyHalf, bladeNew)
        let hi = max(ex.x + bodyHalf, bladeNew)

        var removed: CGFloat = 0
        for c in idx(lo)...idx(hi) {
            if h[c] > keep {
                removed += h[c] - keep
                h[c] = keep
            }
        }
        guard removed > 0.001 else { return }
        dirty = true

        let step = ex.dir > 0 ? 1 : -1
        var c = idx(bladeNew) + step
        var carry = removed
        while carry > 0.001 && c >= 0 && c < cols {
            let room = max(0, maxHeight - h[c])
            let put = min(room, carry)
            h[c] += put
            carry -= put
            c += step
        }
    }
}
