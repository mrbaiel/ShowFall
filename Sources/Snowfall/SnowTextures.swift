import AppKit
import SpriteKit

/// Все текстуры рисуются кодом, внешних картинок нет
enum SnowTextures {
    static let soft: SKTexture = SnowTextures.makeSoft()
    static let crystal: SKTexture = SnowTextures.makeCrystal()
    static let ball: SKTexture = SnowTextures.makeBall()
    static let snowman: SKTexture = SnowTextures.makeSnowman()
    static let hat: SKTexture = SnowTextures.makeHat()
    static let tree: SKTexture = SnowTextures.makeTree()
    static let excavator: SKTexture = SnowTextures.makeExcavator()

    /// Мягкая круглая снежинка
    private static func makeSoft() -> SKTexture {
        let side: CGFloat = 32
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let gradient = NSGradient(
                colors: [.white, NSColor.white.withAlphaComponent(0.0)],
                atLocations: [0.35, 1.0],
                colorSpace: .deviceRGB
            )
            gradient?.draw(in: rect, relativeCenterPosition: .zero)
            return true
        }
        return SKTexture(image: image)
    }

    /// Шестилучевая снежинка для крупных ближних хлопьев
    private static func makeCrystal() -> SKTexture {
        let s: CGFloat = 64
        let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let c = NSPoint(x: s / 2, y: s / 2)
            let path = NSBezierPath()
            path.lineWidth = 3
            path.lineCapStyle = .round
            let marks: [CGFloat] = [14, 21]
            let sides: [CGFloat] = [-1, 1]
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3
                let dx = cos(a)
                let dy = sin(a)
                path.move(to: c)
                path.line(to: NSPoint(x: c.x + dx * 28, y: c.y + dy * 28))
                for t in marks {
                    let bx = c.x + dx * t
                    let by = c.y + dy * t
                    let len: CGFloat = t < 15 ? 8 : 6
                    for side in sides {
                        let ba = a + side * .pi / 3
                        path.move(to: NSPoint(x: bx, y: by))
                        path.line(to: NSPoint(x: bx + cos(ba) * len, y: by + sin(ba) * len))
                    }
                }
            }
            NSColor.white.setStroke()
            path.stroke()
            let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0)])
            glow?.draw(in: NSBezierPath(ovalIn: NSRect(x: 18, y: 18, width: 28, height: 28)), relativeCenterPosition: .zero)
            return true
        }
        return SKTexture(image: image)
    }

    /// Снежный шар с пятнышками, чтобы было видно вращение
    private static func makeBall() -> SKTexture {
        let s: CGFloat = 64
        let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            let shade = NSColor(calibratedRed: 0.78, green: 0.86, blue: 0.95, alpha: 1)
            NSGradient(colors: [NSColor.white, shade])?
                .draw(in: circle, relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
            NSColor(calibratedRed: 0.62, green: 0.74, blue: 0.88, alpha: 1).setStroke()
            circle.lineWidth = 2
            circle.stroke()

            NSColor(calibratedRed: 0.68, green: 0.79, blue: 0.91, alpha: 1).setFill()
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(42, 40, 5), (22, 26, 4), (36, 14, 3.2)]
            for (x, y, r) in spots {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
            }
            return true
        }
        return SKTexture(image: image)
    }

    /// Колпак Деда Мороза: красный, с меховой оторочкой и помпоном на кончике, загнутым вправо.
    /// Рисуется в текущий графический контекст: cx это центр, y0 это низ оторочки.
    private static func paintSantaHat(cx: CGFloat, y0: CGFloat) {
        let red = NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.17, alpha: 1)
        let redDark = NSColor(calibratedRed: 0.62, green: 0.12, blue: 0.12, alpha: 1)
        let fur = NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1)
        let furEdge = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.88, alpha: 1)

        let hat = NSBezierPath()
        hat.move(to: NSPoint(x: cx - 21, y: y0 + 7))
        hat.curve(to: NSPoint(x: cx + 19, y: y0 + 33),
                  controlPoint1: NSPoint(x: cx - 20, y: y0 + 30),
                  controlPoint2: NSPoint(x: cx + 6, y: y0 + 42))
        hat.curve(to: NSPoint(x: cx + 21, y: y0 + 7),
                  controlPoint1: NSPoint(x: cx + 25, y: y0 + 24),
                  controlPoint2: NSPoint(x: cx + 22, y: y0 + 14))
        hat.close()
        red.setFill()
        hat.fill()
        redDark.setStroke()
        hat.lineWidth = 1.6
        hat.stroke()

        let pomp = NSBezierPath(ovalIn: NSRect(x: cx + 14, y: y0 + 26, width: 11, height: 11))
        fur.setFill()
        pomp.fill()
        furEdge.setStroke()
        pomp.lineWidth = 1.5
        pomp.stroke()

        let brim = NSBezierPath(roundedRect: NSRect(x: cx - 24, y: y0, width: 48, height: 12),
                                xRadius: 6, yRadius: 6)
        fur.setFill()
        brim.fill()
        furEdge.setStroke()
        brim.lineWidth = 1.6
        brim.stroke()
    }

    /// Колпак отдельно: слетает, когда снеговика разбивают (56x52 условных единицы)
    private static func makeHat() -> SKTexture {
        let image = NSImage(size: NSSize(width: 56, height: 52), flipped: false) { _ in
            SnowTextures.paintSantaHat(cx: 26, y0: 2)
            return true
        }
        return SKTexture(image: image)
    }

    /// Плоский снеговик как на рисунке-образце: кремовый снег с лавандовыми тенями, колпак Деда Мороза,
    /// чёрные глазки, морковка, улыбка из точек, красный шарф с хвостом, руки-веточки с развилками.
    /// Рисуем в 4x (128x172), на экране он 32x43 pt.
    private static func makeSnowman() -> SKTexture {
        let image = NSImage(size: NSSize(width: 128, height: 172), flipped: false) { _ in
            let snow0 = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.95, alpha: 1)
            let snow1 = NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.96, alpha: 1)
            let snow2 = NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.91, alpha: 1)
            let edge = NSColor(calibratedRed: 0.66, green: 0.66, blue: 0.84, alpha: 1)
            let coal = NSColor(calibratedRed: 0.17, green: 0.07, blue: 0.08, alpha: 1)
            let scarfRed = NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.21, alpha: 1)
            let scarfDark = NSColor(calibratedRed: 0.66, green: 0.15, blue: 0.14, alpha: 1)

            func ball(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
                let p = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                NSGradient(colors: [snow0, snow1, snow2], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)?
                    .draw(in: p, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
                edge.setStroke()
                p.lineWidth = 2.4
                p.stroke()
            }

            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
            }

            // Руки-веточки с развилками (за шарами)
            NSColor(calibratedRed: 0.45, green: 0.29, blue: 0.16, alpha: 1).setStroke()
            let arms = NSBezierPath()
            arms.lineWidth = 4
            arms.lineCapStyle = .round
            let signs: [CGFloat] = [-1, 1]
            for sgn in signs {
                let ax: (CGFloat) -> CGFloat = { 64 + sgn * $0 }
                arms.move(to: NSPoint(x: ax(20), y: 80))
                arms.line(to: NSPoint(x: ax(52), y: 100))
                arms.move(to: NSPoint(x: ax(36), y: 90))
                arms.line(to: NSPoint(x: ax(42), y: 108))
                arms.move(to: NSPoint(x: ax(44), y: 95))
                arms.line(to: NSPoint(x: ax(58), y: 92))
            }
            arms.stroke()

            ball(64, 34, 34)
            ball(64, 80, 24.8)
            ball(64, 115.6, 20.8)

            // Шарф: хвост спереди и повязка
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 74, y: 94))
            tail.line(to: NSPoint(x: 90, y: 94))
            tail.line(to: NSPoint(x: 94, y: 64))
            tail.line(to: NSPoint(x: 80, y: 66))
            tail.close()
            scarfRed.setFill()
            tail.fill()
            scarfDark.setStroke()
            tail.lineWidth = 2
            tail.stroke()

            let band = NSBezierPath(roundedRect: NSRect(x: 40, y: 92, width: 48, height: 13),
                                    xRadius: 6.5, yRadius: 6.5)
            scarfRed.setFill()
            band.fill()
            scarfDark.setStroke()
            band.lineWidth = 2
            band.stroke()

            // Лицо: чёрные овальные глазки, морковка влево-вниз, улыбка из пяти точек
            coal.setFill()
            NSBezierPath(ovalIn: NSRect(x: 55 - 3.2, y: 116 - 4.2, width: 6.4, height: 8.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 73 - 3.2, y: 116 - 4.2, width: 6.4, height: 8.4)).fill()

            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: 66, y: 114.5))
            nose.line(to: NSPoint(x: 66, y: 108.5))
            nose.line(to: NSPoint(x: 44, y: 111))
            nose.close()
            NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.28, alpha: 1),
                                NSColor(calibratedRed: 0.93, green: 0.45, blue: 0.08, alpha: 1)])?
                .draw(in: nose, angle: -90)
            NSColor(calibratedRed: 0.72, green: 0.32, blue: 0.05, alpha: 1).setStroke()
            nose.lineWidth = 1.2
            nose.stroke()

            for k in 0..<5 {
                let a = CGFloat.pi * (1.2 + 0.15 * CGFloat(k))
                dot(64 + 8.5 * cos(a), 110 + 8.5 * sin(a), 1.5, coal)
            }

            SnowTextures.paintSantaHat(cx: 64, y0: 121)
            return true
        }
        return SKTexture(image: image)
    }

    /// Ёлка в снегу (56x80 условных единиц, якорь внизу по центру)
    private static func makeTree() -> SKTexture {
        let image = NSImage(size: NSSize(width: 56, height: 80), flipped: false) { _ in
            NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.17, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 24, y: 0, width: 8, height: 12)).fill()

            let green = NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.24, alpha: 1)
            let dark = NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.16, alpha: 1)
            // ярусы: низ, верх, полуширина
            let tiers: [(CGFloat, CGFloat, CGFloat)] = [(8, 38, 25), (26, 58, 20), (46, 78, 15)]
            for (yb, yt, hw) in tiers {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 28 - hw, y: yb))
                p.line(to: NSPoint(x: 28, y: yt))
                p.line(to: NSPoint(x: 28 + hw, y: yb))
                p.close()
                green.setFill()
                p.fill()
                dark.setStroke()
                p.lineWidth = 1
                p.stroke()
            }

            NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
            for (yb, yt, hw) in tiers {
                let th = yt - yb
                let cap = NSBezierPath()
                cap.move(to: NSPoint(x: 28, y: yt))
                cap.line(to: NSPoint(x: 28 - hw * 0.5, y: yt - th * 0.5))
                cap.line(to: NSPoint(x: 28 - hw * 0.2, y: yt - th * 0.42))
                cap.line(to: NSPoint(x: 28, y: yt - th * 0.55))
                cap.line(to: NSPoint(x: 28 + hw * 0.2, y: yt - th * 0.42))
                cap.line(to: NSPoint(x: 28 + hw * 0.5, y: yt - th * 0.5))
                cap.close()
                cap.fill()
            }
            return true
        }
        return SKTexture(image: image)
    }

    /// Мини-погрузчик со снегоочистителем для плоского режима (120x80 условных единиц, на экране 60x40 pt).
    /// Смотрит вправо, снегоочиститель впереди. Имя текстуры осталось прежним (excavator).
    private static func makeExcavator() -> SKTexture {
        let image = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { _ in
            let outline = NSColor(calibratedRed: 0.30, green: 0.14, blue: 0.05, alpha: 1)
            let orange = NSColor(calibratedRed: 0.97, green: 0.52, blue: 0.13, alpha: 1)
            let black = NSColor(calibratedWhite: 0.14, alpha: 1)
            let graphite = NSColor(calibratedWhite: 0.28, alpha: 1)
            let steel = NSColor(calibratedWhite: 0.80, alpha: 1)
            let glass = NSColor(calibratedRed: 0.72, green: 0.89, blue: 1.0, alpha: 1)
            let cream = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.94, alpha: 1)
            let coal = NSColor(calibratedWhite: 0.12, alpha: 1)

            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: NSColor) {
                let p = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
                fill.setFill()
                p.fill()
                outline.setStroke()
                p.lineWidth = 1.5
                p.stroke()
            }

            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
            }

            // Выбрасывающая труба с козырьком
            let tube = NSBezierPath()
            tube.move(to: NSPoint(x: 84, y: 38))
            tube.line(to: NSPoint(x: 95, y: 38))
            tube.line(to: NSPoint(x: 99, y: 62))
            tube.line(to: NSPoint(x: 90, y: 62))
            tube.close()
            black.setFill()
            tube.fill()
            rrect(88, 60, 20, 6, 3, black)

            // Широкий чёрный корпус снегоочистителя с вращающейся «звездой» шнека на торце
            rrect(72, 8, 46, 32, 9, black)
            dot(95, 24, 11, graphite)
            let star = NSBezierPath()
            star.lineWidth = 2.2
            star.lineCapStyle = .round
            for k in 0..<3 {
                let a = CGFloat(k) * CGFloat.pi / 3
                star.move(to: NSPoint(x: 95 - 9.5 * cos(a), y: 24 - 9.5 * sin(a)))
                star.line(to: NSPoint(x: 95 + 9.5 * cos(a), y: 24 + 9.5 * sin(a)))
            }
            steel.setStroke()
            star.stroke()
            dot(95, 24, 2.4, orange)
            rrect(104, 5, 14, 4, 2, steel)

            // Лапа погрузчика
            let arm = NSBezierPath()
            arm.move(to: NSPoint(x: 30, y: 44))
            arm.line(to: NSPoint(x: 76, y: 24))
            arm.lineCapStyle = .round
            outline.setStroke()
            arm.lineWidth = 9
            arm.stroke()
            orange.setStroke()
            arm.lineWidth = 6
            arm.stroke()

            // Корпус и моторный отсек
            rrect(6, 16, 64, 22, 8, orange)
            rrect(4, 30, 26, 15, 6, orange)

            // Кабина со стеклом, водитель-снеговичок и крыша
            rrect(28, 36, 30, 32, 8, graphite)
            rrect(31, 39, 24, 26, 6, glass)
            dot(43, 52, 6.5, cream)
            let hat = NSBezierPath()
            hat.move(to: NSPoint(x: 37, y: 56))
            hat.line(to: NSPoint(x: 48, y: 64))
            hat.line(to: NSPoint(x: 49, y: 56))
            hat.close()
            NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.17, alpha: 1).setFill()
            hat.fill()
            rrect(36.5, 54.5, 13, 3.4, 1.7, cream)
            dot(49, 63, 2.2, cream)
            dot(41, 52.5, 0.9, coal)
            dot(45.5, 52.5, 0.9, coal)
            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: 48.5, y: 51.6))
            nose.line(to: NSPoint(x: 53, y: 50.8))
            nose.line(to: NSPoint(x: 48.5, y: 50))
            nose.close()
            NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.10, alpha: 1).setFill()
            nose.fill()

            rrect(26, 66, 34, 6, 3, graphite)
            dot(58, 73, 3, NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.60, alpha: 1))
            dot(30, 74, 3.2, NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.10, alpha: 1))

            // Колёса с оранжевыми дисками
            let wheels: [CGFloat] = [22, 58]
            for cx in wheels {
                dot(cx, 14, 13, black)
                dot(cx, 14, 8, orange)
                dot(cx, 14, 3, steel)
            }

            // Снег из трубы
            let snowEdge = NSColor(calibratedRed: 0.70, green: 0.79, blue: 0.92, alpha: 1)
            let puffs: [(CGFloat, CGFloat, CGFloat)] = [(106, 68, 3.8), (112, 72, 3.2), (117, 69, 2.6)]
            for (x, y, r) in puffs {
                snowEdge.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - r - 0.8, y: y - r - 0.8, width: 2 * r + 1.6, height: 2 * r + 1.6)).fill()
                dot(x, y, r, NSColor.white)
            }
            return true
        }
        return SKTexture(image: image)
    }
}
