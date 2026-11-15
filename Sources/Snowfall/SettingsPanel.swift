import AppKit

/// Окно настроек: ползунки для всего, включая количество и время жизни снеговиков, ёлок и экскаваторов
final class SettingsPanel: NSObject {
    typealias Path = WritableKeyPath<SnowSettings, CGFloat>

    struct Row {
        let title: String
        let keyPath: Path
        let range: ClosedRange<Double>
        let integer: Bool
        let format: (CGFloat) -> String
    }

    private let panel: NSPanel
    private let sections: [(String, [Row])]
    private let rows: [Row]
    private var valueLabels: [NSTextField] = []
    private let onChange: (Path, CGFloat) -> Void

    init(initial: SnowSettings, onChange: @escaping (Path, CGFloat) -> Void) {
        let made = SettingsPanel.makeSections()
        self.sections = made
        self.rows = made.flatMap { $0.1 }
        self.onChange = onChange
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "Snowfall: настройки"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        buildUI(initial: initial)
    }

    func show() {
        if !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Описание ползунков

    private static func makeSections() -> [(String, [Row])] {
        let plain: (CGFloat) -> String = { "\(Int($0.rounded()))" }
        let mult: (CGFloat) -> String = { String(format: "×%.1f", Double($0)) }
        let cm: (CGFloat) -> String = { $0 <= 0.05 ? "выкл" : String(format: "%.1f см", Double($0)) }
        let pt: (CGFloat) -> String = { "\(Int($0.rounded())) pt" }
        let life: (CGFloat) -> String = { $0 >= 600 ? "∞" : "\(Int($0.rounded())) с" }

        return [
            ("Снегопад", [
                Row(title: "Количество снега", keyPath: \SnowSettings.amount, range: 10...120, integer: false, format: plain),
                Row(title: "Размер снежинок", keyPath: \SnowSettings.size, range: 0.5...2.5, integer: false, format: mult),
                Row(title: "Скорость падения", keyPath: \SnowSettings.speed, range: 0.5...3.0, integer: false, format: mult)
            ]),
            ("Курсор", [
                Row(title: "Радиус отталкивания", keyPath: \SnowSettings.repelCM, range: 0...3, integer: false, format: cm),
                Row(title: "Сила отталкивания", keyPath: \SnowSettings.repelPower, range: 5...100, integer: false, format: plain)
            ]),
            ("Сугроб внизу", [
                Row(title: "Максимальная высота", keyPath: \SnowSettings.groundMax, range: 4...50, integer: false, format: pt)
            ]),
            ("Снеговики", [
                Row(title: "Сколько одновременно", keyPath: \SnowSettings.snowmenMax, range: 0...8, integer: true, format: plain),
                Row(title: "Время жизни", keyPath: \SnowSettings.snowmenLife, range: 10...600, integer: false, format: life)
            ]),
            ("Ёлки", [
                Row(title: "Сколько одновременно", keyPath: \SnowSettings.treesMax, range: 0...12, integer: true, format: plain),
                Row(title: "Время жизни", keyPath: \SnowSettings.treesLife, range: 10...600, integer: false, format: life)
            ]),
            ("Снегоуборщики", [
                Row(title: "Сколько одновременно", keyPath: \SnowSettings.excavatorsMax, range: 0...3, integer: true, format: plain),
                Row(title: "Время работы", keyPath: \SnowSettings.excavatorLife, range: 10...600, integer: false, format: life)
            ])
        ]
    }

    // MARK: - Интерфейс

    private func buildUI(initial: SnowSettings) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        var tag = 0
        for (title, group) in sections {
            let head = NSTextField(labelWithString: title)
            head.font = NSFont.boldSystemFont(ofSize: 12)
            if let last = stack.arrangedSubviews.last {
                stack.setCustomSpacing(14, after: last)
            }
            stack.addArrangedSubview(head)

            for row in group {
                let value = initial[keyPath: row.keyPath]

                let label = NSTextField(labelWithString: row.title)
                label.font = NSFont.systemFont(ofSize: 12)
                label.widthAnchor.constraint(equalToConstant: 230).isActive = true

                let slider = NSSlider(
                    value: Double(value),
                    minValue: row.range.lowerBound,
                    maxValue: row.range.upperBound,
                    target: self,
                    action: #selector(sliderMoved(_:))
                )
                slider.tag = tag
                slider.isContinuous = true
                slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
                if row.integer {
                    slider.numberOfTickMarks = Int(row.range.upperBound - row.range.lowerBound) + 1
                    slider.allowsTickMarkValuesOnly = true
                }

                let valueLabel = NSTextField(labelWithString: row.format(value))
                valueLabel.alignment = .right
                valueLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
                valueLabels.append(valueLabel)

                let line = NSStackView(views: [label, slider, valueLabel])
                line.orientation = .horizontal
                line.spacing = 10
                stack.addArrangedSubview(line)
                tag += 1
            }
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        panel.contentView = content
        panel.setContentSize(stack.fittingSize)
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let row = rows[sender.tag]
        let v = CGFloat(sender.doubleValue)
        valueLabels[sender.tag].stringValue = row.format(v)
        onChange(row.keyPath, v)
    }
}
