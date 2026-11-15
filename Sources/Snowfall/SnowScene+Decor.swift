import AppKit
import SpriteKit

/// Снеговики и ёлки: появление, срок жизни, лимиты
extension SnowScene {
    func lifetimeFor(_ kind: Decor.Kind) -> TimeInterval {
        return lifetimeSeconds(kind == .snowman ? settings.snowmenLife : settings.treesLife)
    }

    /// Сколько фигур уже стоит или строится (места на окнах занимают slots)
    func count(_ kind: Decor.Kind) -> Int {
        var n = 0
        for list in slots.values {
            for s in list where s.kind == kind { n += 1 }
        }
        if kind == .tree {
            for d in decors where d.kind == .tree && d.windowID == nil { n += 1 }
        }
        return n
    }

    func tickDecor(now: TimeInterval) {
        expireDecor(now: now)

        if now >= nextSnowman {
            nextSnowman = now + Double.random(in: 6...16)
            if count(.snowman) < Int(settings.snowmenMax.rounded()) { spawnSnowman() }
        }
        if now >= nextTree {
            nextTree = now + Double.random(in: 5...14)
            if count(.tree) < Int(settings.treesMax.rounded()) { spawnTree(now: now) }
        }
    }

    private func expireDecor(now: TimeInterval) {
        // Срок жизни считаем по текущему значению ползунка
        for d in decors {
            let life = lifetimeFor(d.kind) * d.jitter
            if life.isFinite && now - d.born > life { retire(d) }
        }
        // Лимит уменьшили: самые старые тают
        let kinds: [Decor.Kind] = [.snowman, .tree]
        for kind in kinds {
            let limit = Int((kind == .snowman ? settings.snowmenMax : settings.treesMax).rounded())
            let items = decors.filter { $0.kind == kind }.sorted { $0.born < $1.born }
            if items.count > limit {
                for d in items.prefix(items.count - limit) { retire(d) }
            }
        }
    }

    /// Фигура тает: уменьшается и исчезает
    func retire(_ d: Decor) {
        decors.removeAll { $0 === d }
        removeSlot(for: d)
        if let parent = d.node.parent {
            puff(at: convert(d.node.position, from: parent), count: 5)
        }
        d.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.05, duration: 0.5),
                SKAction.fadeOut(withDuration: 0.5)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func removeSlot(for d: Decor) {
        guard let id = d.windowID else { return }
        if var list = slots[id],
           let i = list.firstIndex(where: { $0.kind == d.kind && abs($0.x - d.localX) < 0.5 }) {
            list.remove(at: i)
            slots[id] = list
        }
    }

    func retireGroundDecor() {
        for d in decors where d.windowID == nil { retire(d) }
    }

    /// Ёлки на земле стоят на сугробе; экскаватор сносит те, что попали под отвал
    func followGround() {
        for d in decors where d.windowID == nil {
            d.node.position.y = ground.surfaceY(at: d.localX) - 1
        }
        guard !ground.excavators.isEmpty else { return }
        for ex in ground.excavators {
            let bladeX = ex.x + ex.dir * 29
            for d in decors where d.windowID == nil && d.kind == .tree && abs(d.localX - bladeX) < 14 {
                knockDown(d, direction: ex.dir)
            }
        }
    }

    func knockDown(_ d: Decor, direction: CGFloat) {
        guard !d.fallen else { return }
        d.fallen = true
        decors.removeAll { $0 === d }
        let parent: SKNode = d.node.parent ?? self
        puff(at: convert(d.node.position, from: parent), count: 8)
        d.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.rotate(byAngle: -direction * 1.4, duration: 0.45),
                SKAction.fadeOut(withDuration: 0.5)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Где появляться

    /// Окна, на которых снега уже достаточно
    func matureWindows() -> [SnowWindow] {
        guard settings.accumulate else { return [] }
        return lastWindows.values.filter {
            (capGeom[$0.id]?.h ?? 0) >= SnowTuning.matureHeight && $0.rect.width >= 200
        }
    }

    func spawnSnowman() {
        guard let w = matureWindows().randomElement(), let g = capGeom[w.id] else { return }
        _ = tryStartSnowman(for: w, segs: g.segs)
    }

    func spawnTree(now: TimeInterval) {
        let candidates = matureWindows()
        var options: [Bool] = [] // true = на окне, false = на земле
        if settings.ground { options.append(false) }
        if !candidates.isEmpty { options.append(true) }
        guard let onWindow = options.randomElement() else { return }

        if onWindow {
            if let w = candidates.randomElement(), let g = capGeom[w.id] {
                spawnCapTree(for: w, segs: g.segs, now: now)
            }
        } else {
            spawnGroundTree(now: now)
        }
    }

    private func spawnGroundTree(now: TimeInterval) {
        guard size.width > 120 else { return }
        let existing = decors.filter { $0.kind == .tree && $0.windowID == nil }
        for _ in 0..<6 {
            let x = CGFloat.random(in: 40...(size.width - 40))
            if existing.contains(where: { abs($0.localX - x) < 45 }) { continue }

            let t = CGFloat.random(in: 0...1)
            let height = 26 + 36 * pow(t, 1.4) // чаще небольшие, иногда повыше
            let node = makeTreeNode(height: height)
            node.position = CGPoint(x: x, y: ground.surfaceY(at: x) - 1)
            groundDecor.addChild(node)
            appear(node)
            decors.append(Decor(kind: .tree, node: node, windowID: nil, localX: x, born: now))
            return
        }
    }

    private func spawnCapTree(for w: SnowWindow, segs: [Segment], now: TimeInterval) {
        let wide = segs.filter { $0.x1 - $0.x0 > 90 }
        guard !wide.isEmpty else { return }
        let existing = slots[w.id] ?? []

        for _ in 0..<6 {
            guard let s = wide.randomElement() else { return }
            let gx = CGFloat.random(in: (s.x0 + 30)...(s.x1 - 30))
            let lx = gx - w.rect.minX
            if existing.contains(where: { abs($0.x - lx) < 45 }) { continue }

            let holder = holders[w.id] ?? makeHolder(id: w.id)
            let node = makeTreeNode(height: CGFloat.random(in: 16...32))
            node.position = CGPoint(x: lx, y: surfaceY(id: w.id, localX: lx) - 0.5)
            holder.addChild(node)
            appear(node)
            slots[w.id, default: []].append(Slot(x: lx, kind: .tree))
            decors.append(Decor(kind: .tree, node: node, windowID: w.id, localX: lx, born: now))
            return
        }
    }

    func makeHolder(id: Int) -> SKNode {
        let holder = SKNode()
        holder.zPosition = 12
        if let w = lastWindows[id] {
            holder.position = CGPoint(x: w.rect.minX - screenFrame.minX, y: sceneTopY(of: w.rect) - 1)
        }
        addChild(holder)
        holders[id] = holder
        return holder
    }

    /// Фигура «вырастает» из снега
    private func appear(_ node: SKNode) {
        node.setScale(0.05)
        let grow = SKAction.scale(to: 1, duration: 0.6)
        grow.timingMode = .easeOut
        node.run(grow)
    }

    /// Ёлка с гирляндой (гирлянда скрыта до клика)
    func makeTreeNode(height h: CGFloat) -> SKSpriteNode {
        // В 3D-режиме спрайт невидим и служит только «прокси»: по нему идут клики и анимации,
        // а рисует ёлку 3D-модель (Scene3D повторяет его положение, масштаб, поворот и прозрачность)
        let tree = SKSpriteNode(texture: use3D ? nil : SnowTextures.tree)
        tree.color = .clear
        tree.size = CGSize(width: h * 0.7, height: h)
        tree.anchorPoint = CGPoint(x: 0.5, y: 0)

        let lights = SKNode()
        lights.name = "lights"
        lights.zPosition = 1
        lights.isHidden = true

        // Точки гирлянды в координатах текстуры 56x80
        let spots: [(CGFloat, CGFloat)] = [
            (28, 72), (25, 62), (32, 60), (22, 42), (33, 44), (28, 50),
            (23, 28), (33, 26), (16, 18), (28, 22), (40, 16)
        ]
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.35, green: 0.80, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.45, green: 1.0, blue: 0.50, alpha: 1)
        ]
        let u = h / 80
        let dot = max(3.5, h * 0.12)
        for (i, p) in spots.enumerated() {
            let light = SKSpriteNode(texture: SnowTextures.soft)
            light.size = CGSize(width: dot, height: dot)
            light.position = CGPoint(x: (p.0 - 28) * u, y: p.1 * u)
            light.color = colors[i % colors.count]
            light.colorBlendFactor = 1
            light.blendMode = .add
            let d = Double.random(in: 0.35...0.9)
            light.run(SKAction.sequence([
                SKAction.wait(forDuration: Double.random(in: 0...0.8)),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.3, duration: d),
                    SKAction.fadeAlpha(to: 1.0, duration: d)
                ]))
            ]))
            lights.addChild(light)
        }
        tree.addChild(lights)
        scene3D.addTree(proxy: tree, height: h)
        return tree
    }

    /// Шар для постройки и обломков: в 3D-режиме спрайт невидим, а рисует его 3D-сфера
    func makeBallNode(radius r: CGFloat) -> SKSpriteNode {
        let ball = SKSpriteNode(texture: use3D ? nil : SnowTextures.ball)
        ball.color = .clear
        ball.size = CGSize(width: r * 2, height: r * 2)
        scene3D.addBall(proxy: ball, radius: r)
        return ball
    }

    // MARK: - Вид ёлок (плоские или 3D)

    /// Включает или выключает гирлянду и в плоской, и в 3D-версии ёлки
    func applyLights(_ d: Decor, animated: Bool) {
        scene3D.setLights(for: d.node, on: d.lit, animated: animated)

        guard let lights = d.node.childNode(withName: "lights") else { return }
        lights.removeAllActions()
        let show = d.lit && !use3D
        if show && animated {
            lights.alpha = 0
            lights.isHidden = false
            lights.run(SKAction.fadeIn(withDuration: 0.4))
        } else {
            lights.alpha = 1
            lights.isHidden = !show
        }
    }

    /// После переключения 3D-режима: плоские ёлки показываем или прячем
    func refreshTreeVisuals() {
        for d in decors {
            if let sprite = d.node as? SKSpriteNode {
                if d.kind == .tree {
                    sprite.texture = use3D ? nil : SnowTextures.tree
                } else {
                    sprite.texture = use3D ? nil : SnowTextures.snowman
                }
            }
            if d.kind == .tree { applyLights(d, animated: false) }
        }
    }

    // MARK: - Снеговики: шарики катятся и собираются

    func tryStartSnowman(for w: SnowWindow, segs: [Segment]) -> Bool {
        let wide = segs.filter { $0.x1 - $0.x0 > 110 }
        guard !wide.isEmpty else { return false }
        let existing = slots[w.id] ?? []

        for _ in 0..<6 {
            guard let s = wide.randomElement() else { return false }
            let gx = CGFloat.random(in: (s.x0 + 45)...(s.x1 - 45))
            let lx = gx - w.rect.minX
            if existing.contains(where: { abs($0.x - lx) < 60 }) { continue }

            let holder = holders[w.id] ?? makeHolder(id: w.id)
            slots[w.id, default: []].append(Slot(x: lx, kind: .snowman))
            buildStep(0, id: w.id, holder: holder, localX: lx, width: w.rect.width, balls: [])
            return true
        }
        return false
    }

    /// Катит шар номер index к месту стройки; потом следующий; в конце собирает снеговика
    private func buildStep(_ index: Int, id: Int, holder: SKNode, localX: CGFloat,
                           width: CGFloat, balls: [SKSpriteNode]) {
        guard holder.parent != nil else { return } // окно уже скрыли, стройка отменяется
        guard index < SnowScene.radii.count else {
            finishSnowman(id: id, holder: holder, localX: localX, balls: balls)
            return
        }

        let r = SnowScene.radii[index]
        let ball = makeBallNode(radius: r)
        ball.zPosition = 12 + CGFloat(index)

        func clamped(_ x: CGFloat) -> CGFloat { return min(max(x, 10), width - 10) }

        let dist = index == 0 ? CGFloat.random(in: 70...130) : CGFloat.random(in: 40...80)
        var dir: CGFloat = Bool.random() ? 1 : -1 // куда катится
        var startX = clamped(localX - dir * dist)
        if abs(startX - localX) < 40 {
            dir = -dir
            startX = clamped(localX - dir * dist)
        }
        let travel: CGFloat = startX < localX ? 1 : -1
        // Нижний шар катится к месту, остальные останавливаются у него и запрыгивают наверх
        let endX = index == 0 ? localX : localX - travel * (SnowScene.radii[0] + r)
        let startScale: CGFloat = index == 0 ? 0.5 : 0.7

        ball.position = CGPoint(x: startX, y: surfaceY(id: id, localX: startX) + r * startScale * 0.9)
        ball.setScale(startScale)
        holder.addChild(ball)

        let duration = max(1.2, TimeInterval(abs(endX - startX) / 22))
        var actions: [SKAction] = [
            roll(id: id, from: startX, to: endX, radius: r, duration: duration, startScale: startScale)
        ]

        if index > 0 {
            let target = CGPoint(
                x: localX,
                y: surfaceY(id: id, localX: localX) + SnowScene.centers[index]
            )
            let hop = SKAction.move(to: target, duration: 0.3)
            hop.timingMode = .easeOut
            actions.append(SKAction.group([
                hop,
                SKAction.rotate(toAngle: 0, duration: 0.3, shortestUnitArc: true)
            ]))
        }

        actions.append(SKAction.run { [weak self, weak holder] in
            guard let self = self, let holder = holder else { return }
            self.buildStep(index + 1, id: id, holder: holder, localX: localX,
                           width: width, balls: balls + [ball])
        })

        ball.run(SKAction.sequence(actions))
    }

    private func roll(id: Int, from x0: CGFloat, to x1: CGFloat, radius: CGFloat,
                      duration: TimeInterval, startScale: CGFloat) -> SKAction {
        return SKAction.customAction(withDuration: duration) { [weak self] node, elapsed in
            guard let self = self else { return }
            let t = min(1, elapsed / CGFloat(duration))
            let x = x0 + (x1 - x0) * t
            let s = startScale + (1 - startScale) * t // шар обрастает снегом
            node.setScale(s)
            node.position = CGPoint(x: x, y: self.surfaceY(id: id, localX: x) + radius * s * 0.9)
            node.zRotation = -(x - x0) / max(radius * s, 1)
        }
    }

    private func finishSnowman(id: Int, holder: SKNode, localX: CGFloat, balls: [SKSpriteNode]) {
        // В 3D-режиме спрайт невидим и служит прокси: по нему идут клики и анимации,
        // а рисует снеговика 3D-модель (Scene3D повторяет его положение, масштаб, поворот и прозрачность)
        let man = SKSpriteNode(texture: use3D ? nil : SnowTextures.snowman)
        man.color = .clear
        scene3D.addSnowman(proxy: man)
        man.size = CGSize(width: 32, height: 43)
        man.anchorPoint = CGPoint(x: 0.5, y: 0)
        man.position = CGPoint(x: localX, y: surfaceY(id: id, localX: localX) - 0.7)
        man.zPosition = 20
        man.alpha = 0
        holder.addChild(man)

        // Собрался: упругий «хлопок», а потом иногда весело покачивается
        let pop = SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.25),
                SKAction.scaleX(to: 1.12, y: 0.88, duration: 0.12)
            ]),
            SKAction.scaleX(to: 0.95, y: 1.08, duration: 0.12),
            SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.1)
        ])
        let wobble = SKAction.sequence([
            SKAction.wait(forDuration: 9, withRange: 6),
            SKAction.rotate(byAngle: 0.07, duration: 0.12),
            SKAction.rotate(byAngle: -0.14, duration: 0.2),
            SKAction.rotate(byAngle: 0.07, duration: 0.12)
        ])
        man.run(SKAction.sequence([pop, SKAction.repeatForever(wobble)]))

        for b in balls {
            b.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.35),
                SKAction.removeFromParent()
            ]))
        }

        decors.append(Decor(kind: .snowman, node: man, windowID: id, localX: localX,
                            born: ProcessInfo.processInfo.systemUptime))
    }
}
