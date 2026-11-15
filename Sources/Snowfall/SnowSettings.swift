import CoreGraphics
import Foundation

/// Крайнее правое положение ползунка времени жизни означает «бесконечно»
func lifetimeSeconds(_ v: CGFloat) -> TimeInterval {
    return v >= 600 ? TimeInterval.infinity : TimeInterval(v)
}

/// Настройки; хранятся в UserDefaults
struct SnowSettings {
    var amount: CGFloat = 45          // густота снегопада
    var size: CGFloat = 1.0           // множитель размера снежинок
    var speed: CGFloat = 1.0          // множитель скорости падения
    var repelCM: CGFloat = 1.5        // радиус отталкивания от курсора, см (0 = выкл)
    var repelPower: CGFloat = 50      // сила отталкивания
    var groundMax: CGFloat = 18       // максимальная высота сугроба внизу, pt
    var snowmenMax: CGFloat = 3
    var snowmenLife: CGFloat = 180    // секунд
    var treesMax: CGFloat = 5
    var treesLife: CGFloat = 240
    var excavatorsMax: CGFloat = 1
    var excavatorLife: CGFloat = 90
    var accumulate: Bool = true       // сугробы, снеговики и ёлки на окнах
    var ground: Bool = true           // сугроб внизу экрана и экскаваторы
    var mode3D: Bool = true           // 3D-режим: ёлки, сугробы и экскаваторы объёмные

    static let numeric: [(key: String, path: WritableKeyPath<SnowSettings, CGFloat>)] = [
        (key: "amount", path: \SnowSettings.amount),
        (key: "size", path: \SnowSettings.size),
        (key: "speed", path: \SnowSettings.speed),
        (key: "repelCM", path: \SnowSettings.repelCM),
        (key: "repelPower", path: \SnowSettings.repelPower),
        (key: "groundMax", path: \SnowSettings.groundMax),
        (key: "snowmenMax", path: \SnowSettings.snowmenMax),
        (key: "snowmenLife", path: \SnowSettings.snowmenLife),
        (key: "treesMax", path: \SnowSettings.treesMax),
        (key: "treesLife", path: \SnowSettings.treesLife),
        (key: "excavatorsMax", path: \SnowSettings.excavatorsMax),
        (key: "excavatorLife", path: \SnowSettings.excavatorLife)
    ]

    private static let prefix = "v2_"

    static func load() -> SnowSettings {
        let d = UserDefaults.standard
        var s = SnowSettings()
        for item in numeric {
            if let v = d.object(forKey: prefix + item.key) as? Double {
                s[keyPath: item.path] = CGFloat(v)
            }
        }
        if let v = d.object(forKey: prefix + "accumulate") as? Bool { s.accumulate = v }
        if let v = d.object(forKey: prefix + "ground") as? Bool { s.ground = v }
        if let v = d.object(forKey: prefix + "mode3D") as? Bool { s.mode3D = v }
        return s
    }

    func save() {
        let d = UserDefaults.standard
        for item in SnowSettings.numeric {
            d.set(Double(self[keyPath: item.path]), forKey: SnowSettings.prefix + item.key)
        }
        d.set(accumulate, forKey: SnowSettings.prefix + "accumulate")
        d.set(ground, forKey: SnowSettings.prefix + "ground")
        d.set(mode3D, forKey: SnowSettings.prefix + "mode3D")
    }
}
