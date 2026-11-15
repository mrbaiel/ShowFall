import CoreGraphics

/// Константы, которые удобно крутить руками
enum SnowTuning {
    /// Максимальная высота сугроба на окне, pt
    static let maxCapHeight: CGFloat = 16
    /// С какой высоты сугроба на окне появляются снеговики и ёлки. Для быстрой проверки поставьте 4
    static let matureHeight: CGFloat = 13
    /// Сколько раз в секунду опрашиваем окна
    static let tickRate: Double = 20
    static let framesPerSecond = 30
    /// Сила медленного ветра, pt/с
    static let windStrength: CGFloat = 14
    /// Сколько снежинок на единицу ползунка «Количество»
    static let flakesPerAmount: CGFloat = 22
    static let maxFlakes = 3000
    /// Средняя высота снега внизу (pt), с которой выезжает экскаватор. Для быстрой проверки поставьте 0.5
    static let excavatorMinSnow: CGFloat = 2.5

    // MARK: 3D
    /// Наклон ёлок и экскаваторов к зрителю (радианы): через него видно верх и объём
    static let pitch3D: CGFloat = 0.38
    /// Масштаб ортографической камеры. Если 3D-объекты сдвинуты или вдвое крупнее
    /// своих плоских «двойников», попробуйте 1.0 вместо 0.5
    static let orthoScaleFactor: CGFloat = 0.5
    /// Насколько сугроб «толстый» вглубь экрана относительно его высоты
    static let drift3DDepth: CGFloat = 1.6
}
