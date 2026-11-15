import AppKit
import SpriteKit

/// Прозрачное окно на весь экран, пропускающее клики.
/// Внутри два слоя: снизу 3D (SceneKit), сверху плоский (SpriteKit: снежинки, снеговики, обломки).
final class SnowOverlay: NSWindow {
    private let snowScene: SnowScene

    /// Сообщает модели окон, что сугроб на окне разлетелся от клика
    var onKnock: ((Int, CGFloat) -> Void)? {
        get { return snowScene.onKnock }
        set { snowScene.onKnock = newValue }
    }

    init(screen: NSScreen, settings: SnowSettings) {
        let frame = screen.frame
        snowScene = SnowScene(screen: screen, settings: settings)

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let bounds = NSRect(origin: .zero, size: frame.size)
        let container = NSView(frame: bounds)
        container.wantsLayer = true

        let scnView = snowScene.scene3D.view
        scnView.frame = bounds
        container.addSubview(scnView)

        let skView = SKView(frame: bounds)
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = SnowTuning.framesPerSecond
        skView.presentScene(snowScene)
        container.addSubview(skView)

        contentView = container
        setFrame(frame, display: true)
    }

    func apply(settings: SnowSettings) {
        snowScene.apply(settings: settings)
    }

    func apply(windows: [SnowWindow], removed: [SnowWindow]) {
        snowScene.apply(windows: windows, removed: removed)
    }

    func handleClick(at point: NSPoint) {
        snowScene.handleClick(at: point)
    }

    func clearWindowSnow() {
        snowScene.clearWindowSnow()
    }

    func setActive(_ active: Bool) {
        snowScene.isPaused = !active
        snowScene.scene3D.overlayActive = active
        if active {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }
}
