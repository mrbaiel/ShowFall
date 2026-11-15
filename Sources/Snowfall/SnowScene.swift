import AppKit
import SpriteKit

final class SnowScene: SKScene {
    private struct CapKey: Equatable {
        var topY: CGFloat
        var h: CGFloat
        var segs: [Segment]
        var originX: CGFloat
    }

    // Геометрия экрана (координаты сцены: начало внизу слева, как в AppKit)
    let screenFrame: CGRect
    let primaryHeight: CGFloat
    let usableTop: CGFloat      // верх рабочей области, ниже строки меню
    let usableBottom: CGFloat   // низ рабочей области, выше Dock
    let ptPerCM: CGFloat        // сколько pt в сантиметре на этом мониторе

    var settings: SnowSettings
    var flakes: FlakeField!
    var ground: GroundField!
    let groundDecor = SKNode()
    /// 3D-слой под плоской сценой (сугробы, ёлки, экскаваторы)
    let scene3D: Scene3D
    var onKnock: ((Int, CGFloat) -> Void)?

    var use3D: Bool { return settings.mode3D }

    // Сугробы на окнах
    var capNodes: [Int: SKShapeNode] = [:]
    private var capKeys: [Int: CapKey] = [:]
    var capHeights: [Int: CGFloat] = [:]
    var capGeom: [Int: CapGeom] = [:]
    var lastWindows: [Int: SnowWindow] = [:]

    // Снеговики и ёлки
    var holders: [Int: SKNode] = [:]
    var slots: [Int: [Slot]] = [:]
    var decors: [Decor] = []
    var nextSnowman: TimeInterval = 0
    var nextTree: TimeInterval = 0

    private var lastTime: TimeInterval = 0
    private var decorClock: TimeInterval = 0

    /// Радиусы трёх шаров снеговика и высоты их центров над поверхностью сугроба
    static let radii: [CGFloat] = [8.5, 6.2, 5.2]
    static let centers: [CGFloat] = [7.8, 19.3, 28.2]
    /// Высоты центров шаров в готовой текстуре снеговика (от низа спрайта)
    static let textureCenters: [CGFloat] = [8.5, 20.0, 28.9]

    init(screen: NSScreen, settings: SnowSettings) {
        screenFrame = screen.frame
        primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        usableTop = screen.visibleFrame.maxY - screen.frame.minY
        usableBottom = screen.visibleFrame.minY - screen.frame.minY
        ptPerCM = SnowScene.pointsPerCM(for: screen)
        scene3D = Scene3D(size: screen.frame.size)
        self.settings = settings
        super.init(size: screen.frame.size)

        scaleMode = .resizeFill
        backgroundColor = .clear

        flakes = FlakeField(parent: self, size: screen.frame.size, zPosition: 5)
        ground = GroundField(parent: self, width: screen.frame.width, baseY: usableBottom)
        groundDecor.zPosition = 11
        addChild(groundDecor)

        let now = ProcessInfo.processInfo.systemUptime
        nextSnowman = now + 8
        nextTree = now + 3
        apply(settings: settings)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    /// Размер сантиметра по реальным размерам монитора (внешние мониторы иногда врут)
    private static func pointsPerCM(for screen: NSScreen) -> CGFloat {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let num = screen.deviceDescription[key] as? NSNumber {
            let mm = CGDisplayScreenSize(CGDirectDisplayID(num.uint32Value))
            if mm.width > 10 {
                let v = screen.frame.width / (mm.width / 10)
                return min(max(v, 25), 90)
            }
        }
        return 45
    }

    // MARK: - Настройки

    func apply(settings s: SnowSettings) {
        settings = s
        flakes.configure(amount: s.amount, size: s.size, speed: s.speed,
                         repelCM: s.repelCM, repelPower: s.repelPower, ptPerCM: ptPerCM)
        ground.configure(maxHeight: s.groundMax,
                         excavatorMax: Int(s.excavatorsMax.rounded()),
                         excavatorLife: lifetimeSeconds(s.excavatorLife),
                         enabled: s.ground)
        flakes.ground = s.ground ? ground : nil

        // 3D-режим: объёмные сугробы, ёлки и экскаваторы вместо плоских картинок
        if scene3D.enabled3D != s.mode3D { scene3D.enabled3D = s.mode3D }
        if ground.hideVisuals != s.mode3D { ground.hideVisuals = s.mode3D }
        refreshTreeVisuals()

        if !s.ground { retireGroundDecor() }
    }

    // MARK: - Кадр

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 30.0 : min(max(currentTime - lastTime, 0.001), 0.05)
        lastTime = currentTime
        let now = ProcessInfo.processInfo.systemUptime

        // Курсор: снежинки отталкиваются только в маленьком радиусе вокруг него
        let p = NSEvent.mouseLocation
        let m = CGPoint(x: p.x - screenFrame.minX, y: p.y - screenFrame.minY)
        let margin = flakes.repelRadius + 10
        let near = m.x > -margin && m.x < size.width + margin && m.y > -margin && m.y < size.height + margin
        flakes.mouse = near ? m : nil

        flakes.update(dt: CGFloat(dt), time: CGFloat(now))
        if settings.ground { ground.update(dt: CGFloat(dt), now: now) }
        followGround()
        scene3D.sync(scene: self, ground: ground, baseY: usableBottom, now: now)

        decorClock += dt
        if decorClock >= 0.25 {
            decorClock = 0
            tickDecor(now: now)
        }
    }

    // MARK: - Сугробы на окнах

    func apply(windows: [SnowWindow], removed: [SnowWindow]) {
        // 1. Сначала скрытые и сдвинутые окна: их холдеры ещё стоят на старых местах
        for w in removed {
            if let holder = holders[w.id] { dropHolder(holder) }
            forget(w.id)
            if w.height > 1.5 { spawnAvalanche(for: w) }
        }

        var alive = Set<Int>()
        var edges: [FlakeField.Edge] = []
        var geom: [Int: CapGeom] = [:]
        var byID: [Int: SnowWindow] = [:]
        let dx = screenFrame.minX

        for w in windows {
            byID[w.id] = w
            let topY = sceneTopY(of: w.rect)
            let segs = w.segments.filter { $0.x1 - dx > 0 && $0.x0 - dx < size.width }
            guard !segs.isEmpty else { continue }

            // На верхние кромки окон садятся снежинки (кроме окон у самой строки меню)
            if topY > 4 && topY < usableTop - 2 {
                for s in segs {
                    edges.append(FlakeField.Edge(y: topY, x0: s.x0 - dx, x1: s.x1 - dx))
                }
            }

            let h = min(w.height, usableTop - topY)
            guard h > 1, topY > -20 else { continue }

            alive.insert(w.id)
            capHeights[w.id] = h
            geom[w.id] = CapGeom(segs: segs, topY: topY, h: h)

            // Плоская и 3D-версии сугроба поддерживаются обе, показывается одна
            let node = capNodes[w.id] ?? makeCapNode(id: w.id)
            node.isHidden = use3D
            let key = CapKey(topY: topY, h: (h * 5).rounded() / 5, segs: segs, originX: w.rect.minX)
            if capKeys[w.id] != key {
                let strips = capStrips(segments: segs, height: h, originX: w.rect.minX,
                                       seed: CGFloat(w.id % 97))
                node.path = capPath(strips: strips, baseY: topY - 1)
                scene3D.updateCap(id: w.id, baseY: topY - 1, strips: strips)
                capKeys[w.id] = key
            }

            if let holder = holders[w.id] {
                holder.position = CGPoint(x: w.rect.minX - dx, y: topY - 1)
                for child in holder.children where child.name != "debris" {
                    let gx = w.rect.minX + child.position.x
                    child.isHidden = !segs.contains { gx >= $0.x0 + 2 && gx <= $0.x1 - 2 }
                }
            }
        }

        flakes.edges = edges
        capGeom = geom
        lastWindows = byID

        for (id, node) in capNodes where !alive.contains(id) {
            node.removeFromParent()
        }
        capNodes = capNodes.filter { alive.contains($0.key) }
        capKeys = capKeys.filter { alive.contains($0.key) }
        capHeights = capHeights.filter { alive.contains($0.key) }
        scene3D.pruneCaps(keeping: alive)

        // Окно закрыто или на другом столе: холдер прячем, снеговики вернутся вместе с окном
        for (id, holder) in holders { holder.isHidden = !alive.contains(id) }
        if holders.count > 30 {
            for (id, holder) in holders where holder.isHidden {
                holder.removeFromParent()
                forget(id)
            }
        }
    }

    /// Убирает сугробы, снеговиков и ёлки с окон (без анимации)
    func clearWindowSnow() {
        capNodes.values.forEach { $0.removeFromParent() }
        holders.values.forEach { $0.removeFromParent() }
        for d in decors where d.windowID != nil { d.node.removeFromParent() }
        decors.removeAll { $0.windowID != nil }
        capNodes.removeAll()
        capKeys.removeAll()
        capHeights.removeAll()
        capGeom.removeAll()
        holders.removeAll()
        slots.removeAll()
        flakes.edges = []
        scene3D.clearCaps()
    }

    /// Полный сброс (смена экранов)
    func clearSnow() {
        clearWindowSnow()
        for d in decors { d.node.removeFromParent() }
        decors.removeAll()
        ground.clear()
    }

    func forget(_ id: Int) {
        holders[id] = nil
        slots[id] = nil
        capHeights[id] = nil
        decors.removeAll { $0.windowID == id }
    }

    func sceneTopY(of rect: CGRect) -> CGFloat {
        // CoreGraphics (Y вниз, от верха главного экрана) -> координаты этой сцены
        return (primaryHeight - rect.minY) - screenFrame.minY
    }

    func makeCapNode(id: Int) -> SKShapeNode {
        let node = SKShapeNode()
        node.fillColor = NSColor(white: 0.98, alpha: 0.97)
        node.strokeColor = NSColor(calibratedRed: 0.70, green: 0.79, blue: 0.90, alpha: 0.9)
        node.lineWidth = 1
        node.zPosition = 10
        addChild(node)
        capNodes[id] = node
        return node
    }

    /// Профиль поверхности сугроба (0.44...1.0 от высоты), одинаков для шапки и для шариков
    static func profile(_ r: CGFloat, seed: CGFloat) -> CGFloat {
        let a: CGFloat = sin((r + seed) * 0.045)
        let b: CGFloat = sin((r + seed * 1.7) * 0.11)
        return 0.72 + 0.16 * a + 0.12 * b
    }

    /// Высота поверхности сугроба над кромкой окна в точке localX (от левого края окна)
    func surfaceY(id: Int, localX: CGFloat) -> CGFloat {
        let h = capHeights[id] ?? SnowTuning.maxCapHeight
        return h * SnowScene.profile(localX, seed: CGFloat(id % 97))
    }

    /// Профиль сугроба вдоль видимых участков кромки (X в координатах этой сцены).
    /// По нему строится и плоская заливка, и 3D-сетка.
    private func capStrips(segments: [Segment], height: CGFloat,
                           originX: CGFloat, seed: CGFloat) -> [SnowStrip] {
        let dx = screenFrame.minX
        var result: [SnowStrip] = []

        for s in segments {
            var xs: [CGFloat] = []
            var hs: [CGFloat] = []
            var x = s.x0
            while x < s.x1 {
                let edge: CGFloat = min(x - s.x0, s.x1 - x)
                let t: CGFloat = min(1, max(0, edge / 10))
                let taper: CGFloat = t * (2 - t)
                xs.append(x - dx)
                hs.append(height * SnowScene.profile(x - originX, seed: seed) * taper)
                x += 5
            }
            xs.append(s.x1 - dx)
            hs.append(0)
            result.append(SnowStrip(xs: xs, hs: hs))
        }
        return result
    }

    private func capPath(strips: [SnowStrip], baseY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for s in strips {
            guard let first = s.xs.first, let last = s.xs.last else { continue }
            path.move(to: CGPoint(x: first, y: baseY))
            for i in 0..<s.xs.count {
                path.addLine(to: CGPoint(x: s.xs[i], y: baseY + s.hs[i]))
            }
            path.addLine(to: CGPoint(x: last, y: baseY))
            path.closeSubpath()
        }
        return path
    }

    // MARK: - Обвал

    /// Окно скрыли или сдвинули: снег с него осыпается комками
    func spawnAvalanche(for w: SnowWindow) {
        let topY = sceneTopY(of: w.rect)
        guard topY > -50, topY < size.height + 50 else { return }

        for s in w.segments {
            let x0 = s.x0 - screenFrame.minX
            let x1 = s.x1 - screenFrame.minX
            guard x1 > 0, x0 < size.width else { continue }

            let density: CGFloat = min(1, w.height / 8)
            let count = min(60, Int((x1 - x0) / 7 * density))
            guard count > 0 else { continue }

            for _ in 0..<count {
                let clump = SKSpriteNode(texture: SnowTextures.soft)
                let d = CGFloat.random(in: 8...20)
                clump.size = CGSize(width: d, height: d)
                clump.position = CGPoint(
                    x: CGFloat.random(in: x0...x1),
                    y: topY + CGFloat.random(in: 0...w.height)
                )
                clump.zPosition = 11
                addChild(clump)
                runFall(clump, spin: false)
            }
        }
    }

    /// Падение с затуханием, потом узел удаляется
    func runFall(_ node: SKNode, spin: Bool) {
        let duration = TimeInterval.random(in: 0.7...1.3)
        let fall = CGFloat.random(in: 140...420)
        let move = SKAction.moveBy(x: CGFloat.random(in: -30...30), y: -fall, duration: duration)
        move.timingMode = .easeIn
        var parts: [SKAction] = [
            move,
            SKAction.sequence([
                SKAction.wait(forDuration: duration * 0.45),
                SKAction.fadeOut(withDuration: duration * 0.55)
            ])
        ]
        if spin {
            parts.append(SKAction.rotate(byAngle: CGFloat.random(in: -2...2), duration: duration))
        }
        node.run(SKAction.sequence([SKAction.group(parts), SKAction.removeFromParent()]))
    }

    /// Снег сдвинули или окно скрыли: снеговики, ёлки и шарики падают вместе с ним
    func dropHolder(_ holder: SKNode) {
        for child in holder.children {
            child.removeAllActions()
            child.move(toParent: self)
            child.zPosition = 21
            runFall(child, spin: true)
        }
        holder.removeFromParent()
    }
}
