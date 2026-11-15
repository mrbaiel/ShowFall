import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var accumulateItem: NSMenuItem!
    private var groundItem: NSMenuItem!
    private var mode3DItem: NSMenuItem!
    private var settingsPanel: SettingsPanel?

    private var overlays: [SnowOverlay] = []
    private var settings = SnowSettings.load()
    private var isPaused = false

    private let coverage = SnowCoverage()
    private var timer: Timer?
    private var lastTick = Date()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        settingsPanel = SettingsPanel(initial: settings) { [weak self] path, value in
            self?.settingChanged(path, value)
        }
        rebuildOverlays()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // .common, чтобы таймер работал и пока открыто меню
        let t = Timer(timeInterval: 1.0 / SnowTuning.tickRate, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Клики в других приложениях: по ним снеговики ломаются, ёлки зажигаются, сугробы разлетаются.
        // Сам клик при этом уходит приложению под снегом как обычно.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            let p = NSEvent.mouseLocation
            self.overlays.forEach { $0.handleClick(at: p) }
        }
    }

    // MARK: - Меню

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "❄️"

        let menu = NSMenu()

        pauseItem = NSMenuItem(title: "Пауза", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let prefs = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        accumulateItem = NSMenuItem(title: "Сугробы, снеговики и ёлки на окнах", action: #selector(toggleAccumulate), keyEquivalent: "")
        accumulateItem.target = self
        accumulateItem.state = settings.accumulate ? .on : .off
        menu.addItem(accumulateItem)

        groundItem = NSMenuItem(title: "Сугроб внизу и снегоуборщики", action: #selector(toggleGround), keyEquivalent: "")
        groundItem.target = self
        groundItem.state = settings.ground ? .on : .off
        menu.addItem(groundItem)

        mode3DItem = NSMenuItem(title: "3D-режим (снеговики, ёлки, сугробы, снегоуборщики)", action: #selector(toggle3D), keyEquivalent: "")
        mode3DItem.target = self
        mode3DItem.state = settings.mode3D ? .on : .off
        menu.addItem(mode3DItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Действия

    private func settingChanged(_ path: SettingsPanel.Path, _ value: CGFloat) {
        settings[keyPath: path] = value
        settings.save()
        overlays.forEach { $0.apply(settings: settings) }
    }

    @objc private func showSettings() {
        settingsPanel?.show()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        pauseItem.title = isPaused ? "Продолжить" : "Пауза"
        overlays.forEach { $0.setActive(!isPaused) }
        lastTick = Date()
    }

    @objc private func toggleAccumulate() {
        settings.accumulate.toggle()
        accumulateItem.state = settings.accumulate ? .on : .off
        settings.save()
        if !settings.accumulate {
            coverage.reset()
            overlays.forEach { $0.clearWindowSnow() }
        }
        overlays.forEach { $0.apply(settings: settings) }
        lastTick = Date()
    }

    @objc private func toggleGround() {
        settings.ground.toggle()
        groundItem.state = settings.ground ? .on : .off
        settings.save()
        overlays.forEach { $0.apply(settings: settings) }
    }

    @objc private func toggle3D() {
        settings.mode3D.toggle()
        mode3DItem.state = settings.mode3D ? .on : .off
        settings.save()
        overlays.forEach { $0.apply(settings: settings) }
    }

    @objc private func screensChanged() {
        rebuildOverlays()
    }

    @objc private func spaceChanged() {
        // Окна другого рабочего стола не считаем скрытыми: снег и снеговики вернутся вместе с ними
        coverage.spaceChanged()
    }

    // MARK: - Опрос окон

    private func tick() {
        guard !isPaused, settings.accumulate else { return }

        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.5)
        lastTick = now

        // Примерно 16 pt снега за пару минут при средней густоте
        let growth = 0.02 * settings.amount / 45
        let result = coverage.update(dt: dt, growth: growth, maxHeight: SnowTuning.maxCapHeight)
        overlays.forEach { $0.apply(windows: result.windows, removed: result.removed) }
    }

    // MARK: - Окна-оверлеи

    private func rebuildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { SnowOverlay(screen: $0, settings: settings) }
        for overlay in overlays {
            overlay.onKnock = { [weak self] id, factor in
                self?.coverage.knock(id: id, factor: factor)
            }
            overlay.setActive(!isPaused)
        }
    }
}
