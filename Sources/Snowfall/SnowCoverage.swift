import AppKit

/// Видимый участок верхней кромки окна (глобальные координаты X)
struct Segment: Equatable {
    var x0: CGFloat
    var x1: CGFloat
}

struct SnowWindow {
    let id: Int
    /// Координаты CoreGraphics: начало слева сверху главного экрана, Y вниз
    let rect: CGRect
    /// Части верхней кромки, не закрытые другими окнами
    let segments: [Segment]
    /// Текущая высота сугроба в пунктах
    let height: CGFloat
}

/// Следит за окнами и "растит" на них снег. Рисованием не занимается.
final class SnowCoverage {
    private var heights: [Int: CGFloat] = [:]
    /// Сколько секунд окно стоит на месте (снег растёт, только когда окно неподвижно)
    private var still: [Int: TimeInterval] = [:]
    private var previous: [Int: SnowWindow] = [:]
    private var missing: [Int: Int] = [:]
    private let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

    private let missThreshold = 2        // опросов подряд, после которых окно считается скрытым
    private let settleTime: TimeInterval = 1.5

    /// При смене Space окна пропадают из списка, но это не повод устраивать обвал
    func spaceChanged() {
        previous.removeAll()
        missing.removeAll()
    }

    /// Сугроб разлетелся от клика: уменьшаем и даём снегу отрасти заново
    func knock(id: Int, factor: CGFloat) {
        heights[id] = (heights[id] ?? 0) * factor
        still[id] = 0
    }

    func reset() {
        heights.removeAll()
        still.removeAll()
        previous.removeAll()
        missing.removeAll()
    }

    /// windows: текущие окна (спереди назад).
    /// removed: окна, с которых снег должен осыпаться. Это либо скрытые окна,
    /// либо сдвинутые (тогда в removed лежит их СТАРОЕ положение).
    func update(dt: TimeInterval, growth: CGFloat, maxHeight: CGFloat)
        -> (windows: [SnowWindow], removed: [SnowWindow])
    {
        let raw = snapshot()
        let rects = raw.map { $0.rect }

        var ordered: [SnowWindow] = []
        var current: [Int: SnowWindow] = [:]
        var removed: [SnowWindow] = []

        for (i, item) in raw.enumerated() {
            if let old = previous[item.id], hasMoved(from: old.rect, to: item.rect) {
                // Окно двинули: снег осыпается там, где лежал, а на новом месте растёт заново
                if old.height > 1.5 { removed.append(old) }
                heights[item.id] = 0
                still[item.id] = 0
            } else {
                still[item.id] = (still[item.id] ?? 0) + dt
            }

            var h = heights[item.id] ?? 0
            if (still[item.id] ?? 0) >= settleTime {
                h += (maxHeight - h) * min(1, CGFloat(dt) * growth)
            }
            heights[item.id] = h

            let w = SnowWindow(
                id: item.id,
                rect: item.rect,
                segments: visibleSegments(at: i, rects: rects),
                height: h
            )
            ordered.append(w)
            current[item.id] = w
        }

        // Окно считаем скрытым, только если оно пропало на несколько опросов подряд
        var gone: [SnowWindow] = []
        var next = current
        for (id, w) in previous where current[id] == nil {
            let m = (missing[id] ?? 0) + 1
            if m >= missThreshold {
                gone.append(w)
                missing[id] = nil
            } else {
                missing[id] = m
                next[id] = w
            }
        }
        for id in current.keys { missing[id] = nil }

        // Если исчезло почти всё сразу, это смена Space или сон дисплея, а не скрытие окон
        let mass = gone.count >= 2 && gone.count * 10 >= previous.count * 8
        for w in gone {
            if mass { continue } // высоту помним: вернётесь на тот стол, снег будет на месте
            removed.append(w)
            heights[w.id] = nil
            still[w.id] = nil
        }
        previous = next

        return (ordered, removed)
    }

    // MARK: - Окна

    private func hasMoved(from a: CGRect, to b: CGRect) -> Bool {
        return abs(a.minX - b.minX) > 1.5
            || abs(a.minY - b.minY) > 1.5
            || abs(a.width - b.width) > 1.5
    }

    private func snapshot() -> [(id: Int, rect: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [(id: Int, rect: CGRect)] = []
        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.1, rect.width >= 160, rect.height >= 80 else { continue }

            result.append((id: id, rect: rect))
        }
        return result // порядок: от переднего окна к заднему
    }

    /// Верхняя кромка окна минус части, закрытые окнами спереди
    private func visibleSegments(at index: Int, rects: [CGRect]) -> [Segment] {
        let r = rects[index]
        var segs = [Segment(x0: r.minX, x1: r.maxX)]

        for j in 0..<index {
            let o = rects[j]
            guard o.minY <= r.minY, o.maxY > r.minY else { continue }

            var next: [Segment] = []
            for s in segs {
                if o.maxX <= s.x0 || o.minX >= s.x1 {
                    next.append(s)
                    continue
                }
                if o.minX > s.x0 { next.append(Segment(x0: s.x0, x1: o.minX)) }
                if o.maxX < s.x1 { next.append(Segment(x0: o.maxX, x1: s.x1)) }
            }
            segs = next
        }
        return segs.filter { $0.x1 - $0.x0 > 12 }
    }
}
