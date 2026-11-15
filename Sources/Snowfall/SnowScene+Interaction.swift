import AppKit
import SpriteKit

/// Состояние летящего обломка (шара, морковки, комка снега)
private final class DebrisState {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var spin: CGFloat
    var settled = false
    var last: CGFloat = 0

    init(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, spin: CGFloat) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.spin = spin
    }
}

/// Реакция на клики: снеговики ломаются, ёлки включают и выключают гирлянду, сугробы разлетаются
extension SnowScene {
    func handleClick(at global: NSPoint) {
        guard !isPaused else { return }
        let sp = CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        guard sp.x >= 0, sp.x <= size.width, sp.y >= 0, sp.y <= size.height else { return }

        // 1. Снеговики и ёлки (верхние первыми)
        for d in decors.reversed() {
            guard let parent = d.node.parent, !d.node.isHidden, !parent.isHidden else { continue }
            let pt = parent.convert(sp, from: self)
            if d.node.frame.insetBy(dx: -4, dy: -4).contains(pt) {
                if d.kind == .snowman {
                    breakSnowman(d, clickScene: sp)
                } else {
                    toggleLights(d)
                }
                return
            }
        }

        // 2. Сугроб на окне
        let gx = sp.x + screenFrame.minX
        for (id, g) in capGeom {
            guard sp.y >= g.topY - 6, sp.y <= g.topY + g.h + 8 else { continue }
            if g.segs.contains(where: { gx >= $0.x0 && gx <= $0.x1 }) {
                scatterCap(id: id, at: sp)
                return
            }
        }

        // 3. Сугроб внизу экрана
        if settings.ground, sp.y <= ground.surfaceY(at: sp.x) + 8, ground.height(at: sp.x) > 1 {
            scatterGround(at: sp)
        }
    }

    // MARK: - Ёлки

    func toggleLights(_ d: Decor) {
        d.lit.toggle()
        applyLights(d, animated: true)
    }

    // MARK: - Сугробы

    func scatterCap(id: Int, at p: CGPoint) {
        burst(at: p, count: 28, speed: 160, lift: 280)
        onKnock?(id, 0.5)
        capHeights[id] = (capHeights[id] ?? 0) * 0.5
    }

    func scatterGround(at p: CGPoint) {
        let removed = ground.scatter(at: p.x, radius: 55, fraction: 0.75)
        let count = min(40, 12 + Int(removed * 1.2))
        burst(at: CGPoint(x: p.x, y: ground.surfaceY(at: p.x) + 2), count: count, speed: 170, lift: 260)
    }

    /// Комки снега разлетаются по параболе и тают на лету
    func burst(at p: CGPoint, count: Int, speed: CGFloat, lift: CGFloat) {
        for _ in 0..<count {
            let clump = SKSpriteNode(texture: SnowTextures.soft)
            let d = CGFloat.random(in: 6...15)
            clump.size = CGSize(width: d, height: d)
            clump.position = p
            clump.zPosition = 23
            addChild(clump)

            let vx = CGFloat.random(in: -speed...speed)
            let vy = CGFloat.random(in: (lift * 0.35)...lift)
            let life = TimeInterval.random(in: 0.7...1.3)
            let g: CGFloat = 620
            let fly = SKAction.customAction(withDuration: life) { node, t in
                node.position = CGPoint(x: p.x + vx * t, y: p.y + vy * t - 0.5 * g * t * t)
                node.alpha = max(0, 1 - t / CGFloat(life))
            }
            clump.run(SKAction.sequence([fly, SKAction.removeFromParent()]))
        }
    }

    func puff(at p: CGPoint, count: Int) {
        burst(at: p, count: count, speed: 70, lift: 90)
    }

    // MARK: - Снеговик ломается

    func breakSnowman(_ d: Decor, clickScene: CGPoint) {
        guard let id = d.windowID, let holder = d.node.parent else { return }
        let base = d.node.position
        let width = lastWindows[id]?.rect.width ?? 600

        decors.removeAll { $0 === d }
        removeSlot(for: d)
        d.node.removeFromParent()

        // Обломки летят от места удара
        let clickLocal = holder.convert(clickScene, from: self)
        let away: CGFloat = clickLocal.x >= base.x ? -1 : 1

        puff(at: convert(CGPoint(x: base.x, y: base.y + 16), from: holder), count: 10)

        // Три шара: нижний тяжёлый и почти не летит, голова улетает дальше всех
        let speedsX: [ClosedRange<CGFloat>] = [10...40, 40...90, 70...150]
        let speedsY: [ClosedRange<CGFloat>] = [40...80, 90...150, 170...260]
        for i in 0..<3 {
            let r = SnowScene.radii[i]
            let ball = makeBallNode(radius: r)
            let p = CGPoint(x: base.x, y: base.y + SnowScene.textureCenters[i])
            let v = CGVector(dx: away * CGFloat.random(in: speedsX[i]),
                             dy: CGFloat.random(in: speedsY[i]))
            launchPiece(ball, in: holder, windowID: id, width: width, at: p, velocity: v,
                        radius: r, spin: CGFloat.random(in: -6...6), life: 3.5)
        }

        // Морковка, веточки и шарф
        func piece(_ kind: Scene3D.PieceKind, _ color: NSColor, _ w: CGFloat, _ h: CGFloat,
                   _ y: CGFloat, _ dx: CGFloat) {
            let n = SKSpriteNode(color: use3D ? NSColor.clear : color, size: CGSize(width: w, height: h))
            scene3D.addPiece(proxy: n, kind: kind)
            let p = CGPoint(x: base.x + dx, y: base.y + y)
            let v = CGVector(dx: away * CGFloat.random(in: 60...240), dy: CGFloat.random(in: 100...260))
            launchPiece(n, in: holder, windowID: id, width: width, at: p, velocity: v,
                        radius: 1.2, spin: CGFloat.random(in: -10...10), life: 3)
        }
        let orange = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.10, alpha: 1)
        let brown = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.20, alpha: 1)
        let red = NSColor(calibratedRed: 0.80, green: 0.15, blue: 0.15, alpha: 1)
        piece(.carrot, orange, 7, 2.6, 28.2, 2.5)
        piece(.twig, brown, 11, 1.6, 23, -9)
        piece(.twig, brown, 11, 1.6, 23, 9)
        piece(.scarf, red, 12, 3.2, 24.5, 0)

        // Шапочка слетает выше всех
        let hat = SKSpriteNode(texture: use3D ? nil : SnowTextures.hat)
        hat.color = .clear
        hat.size = CGSize(width: 14, height: 13)
        scene3D.addPiece(proxy: hat, kind: .hat)
        launchPiece(hat, in: holder, windowID: id, width: width,
                    at: CGPoint(x: base.x, y: base.y + 37),
                    velocity: CGVector(dx: away * CGFloat.random(in: 40...140),
                                       dy: CGFloat.random(in: 230...330)),
                    radius: 3, spin: away * CGFloat.random(in: 3...9), life: 3.5)

        // Комки снега
        for _ in 0..<8 {
            let n = SKSpriteNode(texture: SnowTextures.soft)
            let s = CGFloat.random(in: 5...10)
            n.size = CGSize(width: s, height: s)
            let p = CGPoint(x: base.x + CGFloat.random(in: -6...6), y: base.y + CGFloat.random(in: 4...36))
            let v = CGVector(dx: CGFloat.random(in: -130...130), dy: CGFloat.random(in: 60...200))
            launchPiece(n, in: holder, windowID: id, width: width, at: p, velocity: v,
                        radius: 2, spin: 0, life: 1.4)
        }
    }

    /// Обломок летит под действием гравитации, отскакивает от сугроба, катится и затухает.
    /// Если слетел с края окна, падает вниз.
    private func launchPiece(_ node: SKNode, in holder: SKNode, windowID id: Int, width: CGFloat,
                             at p: CGPoint, velocity v: CGVector, radius: CGFloat,
                             spin: CGFloat, life: TimeInterval) {
        node.name = "debris"
        node.position = p
        node.zPosition = 22
        holder.addChild(node)

        let st = DebrisState(x: p.x, y: p.y, vx: v.dx, vy: v.dy, spin: spin)
        let sim = SKAction.customAction(withDuration: life) { [weak self] n, elapsed in
            guard let self = self else { return }
            let dt = min(elapsed - st.last, 0.05)
            st.last = elapsed
            if dt <= 0 { return }

            let onWindow = st.x >= 0 && st.x <= width
            if st.settled && !onWindow { st.settled = false }

            if st.settled {
                st.vx *= max(0, 1 - 6 * dt)
                st.spin *= max(0, 1 - 6 * dt)
                st.x += st.vx * dt
            } else {
                st.vy -= 700 * dt
                st.x += st.vx * dt
                st.y += st.vy * dt
            }

            if st.x >= 0 && st.x <= width {
                let floorY = self.surfaceY(id: id, localX: st.x) + radius * 0.6
                if st.settled {
                    st.y = floorY
                } else if st.y <= floorY && st.vy <= 0 {
                    st.y = floorY
                    if abs(st.vy) < 45 {
                        st.settled = true
                        st.vy = 0
                    } else {
                        st.vy = -st.vy * 0.32
                        st.vx *= 0.72
                        st.spin *= 0.8
                    }
                }
            }

            n.position = CGPoint(x: st.x, y: st.y)
            n.zRotation += st.spin * dt
        }
        node.run(SKAction.sequence([sim, SKAction.fadeOut(withDuration: 0.6), SKAction.removeFromParent()]))
    }
}
