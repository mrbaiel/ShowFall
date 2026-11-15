import AppKit
import SceneKit
import SpriteKit

/// 3D-слой: прозрачная SceneKit-сцена под плоским слоем снежинок.
/// Камера ортографическая, 1 единица сцены = 1 pt экрана, поэтому координаты те же,
/// что у плоской сцены. Снеговики, ёлки и снегоуборщики слегка наклонены к зрителю,
/// чтобы был виден объём.
///
/// Снеговики, ёлки и обломки живут в плоской сцене как невидимые «прокси-спрайты»
/// (по ним идут клики и анимации); Scene3D повторяет их положение, масштаб, поворот и прозрачность.
final class Scene3D {
    /// Что разлетается при ударе по снеговику
    enum PieceKind { case carrot, twig, scarf, hat }

    /// Пара «плоский прокси-спрайт и 3D-модель»
    private final class Rig {
        let pitch: SCNNode
        let roll: SCNNode
        let lights: SCNNode?
        weak var proxy: SKNode?

        init(pitch: SCNNode, roll: SCNNode, lights: SCNNode?, proxy: SKNode) {
            self.pitch = pitch
            self.roll = roll
            self.lights = lights
            self.proxy = proxy
        }
    }

    private final class PlowRig {
        let pitch: SCNNode
        let roll: SCNNode
        let flip: SCNNode

        init(pitch: SCNNode, roll: SCNNode, flip: SCNNode) {
            self.pitch = pitch
            self.roll = roll
            self.flip = flip
        }
    }

    let view: SCNView
    private let scene = SCNScene()
    private let content = SCNNode()
    private let size: CGSize

    private let groundNode = SCNNode()
    private var groundRevision = -1
    private var lastGroundBuild: TimeInterval = 0
    private var capModels: [Int: SCNNode] = [:]
    private var rigs: [Rig] = []
    private var plows: [ObjectIdentifier: PlowRig] = [:]

    var enabled3D = true {
        didSet {
            groundRevision = -1
            refreshRendering()
        }
    }
    var overlayActive = true {
        didSet { refreshRendering() }
    }

    init(size: CGSize) {
        self.size = size
        view = SCNView(frame: NSRect(origin: .zero, size: size))
        view.scene = scene
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = SnowTuning.framesPerSecond
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(content)
        content.addChildNode(groundNode)
        buildCameraAndLights()
        refreshRendering()
    }

    private func refreshRendering() {
        view.isHidden = !enabled3D
        view.isPlaying = enabled3D && overlayActive
    }

    private func buildCameraAndLights() {
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(size.height) * Double(SnowTuning.orthoScaleFactor)
        cam.zNear = 10
        cam.zFar = 5000
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = v3(size.width / 2, size.height / 2, 2000)
        scene.rootNode.addChildNode(camNode)
        view.pointOfView = camNode

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        ambient.color = NSColor(calibratedRed: 0.82, green: 0.88, blue: 1.0, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 750
        sun.color = NSColor.white
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = v3(-0.8, -0.55, 0)
        scene.rootNode.addChildNode(sunNode)
    }

    // MARK: - Кадр

    /// Переносит состояние плоской сцены в 3D: фигуры по прокси-спрайтам, сугроб внизу, снегоуборщики
    func sync(scene sk: SKNode, ground: GroundField, baseY: CGFloat, now: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        syncRigs(sk)
        if enabled3D {
            syncGround(ground, baseY: baseY, now: now)
            syncPlows(ground.excavators)
        }
        SCNTransaction.commit()
    }

    private func syncGround(_ ground: GroundField, baseY: CGFloat, now: TimeInterval) {
        groundNode.isHidden = !ground.isEnabled || ground.peak < 0.6
        guard ground.isEnabled else { return }
        guard ground.revision != groundRevision, now - lastGroundBuild > 0.07 else { return }
        groundRevision = ground.revision
        lastGroundBuild = now

        let hs = ground.snapshot()
        var xs: [CGFloat] = []
        for i in 0..<hs.count { xs.append(CGFloat(i) * GroundField.colW) }
        groundNode.geometry = SnowMesh.make(strips: [SnowStrip(xs: xs, hs: hs)])
        groundNode.position = v3(0, baseY, 0)
    }

    /// Логика движения живёт в плоском спрайте; 3D-снегоуборщик повторяет его положение и наклон
    private func syncPlows(_ list: [GroundField.Excavator]) {
        var seen = Set<ObjectIdentifier>()
        for ex in list {
            let id = ObjectIdentifier(ex)
            seen.insert(id)

            let rig: PlowRig
            if let existing = plows[id] {
                rig = existing
            } else {
                rig = makePlowRig()
                content.addChildNode(rig.pitch)
                plows[id] = rig
            }
            rig.pitch.position = v3(ex.node.position.x, ex.node.position.y, 0)
            rig.roll.eulerAngles = v3(0, 0, ex.node.zRotation)
            rig.flip.eulerAngles = v3(0, ex.dir > 0 ? 0 : CGFloat.pi, 0)
        }
        for (id, rig) in plows where !seen.contains(id) {
            rig.pitch.removeFromParentNode()
        }
        plows = plows.filter { seen.contains($0.key) }
    }

    // MARK: - Сугробы на окнах

    func updateCap(id: Int, baseY: CGFloat, strips: [SnowStrip]) {
        let node: SCNNode
        if let existing = capModels[id] {
            node = existing
        } else {
            node = SCNNode()
            content.addChildNode(node)
            capModels[id] = node
        }
        node.geometry = SnowMesh.make(strips: strips)
        node.position = v3(0, baseY, 0)
    }

    func pruneCaps(keeping alive: Set<Int>) {
        for (id, node) in capModels where !alive.contains(id) {
            node.removeFromParentNode()
        }
        capModels = capModels.filter { alive.contains($0.key) }
    }

    func clearCaps() {
        capModels.values.forEach { $0.removeFromParentNode() }
        capModels.removeAll()
    }

    // MARK: - Прокси и модели

    /// Положение, масштаб (рост, «хлопок», таяние), поворот (падение, покачивание)
    /// и прозрачность берём у прокси-спрайта
    private func syncRigs(_ sk: SKNode) {
        rigs.removeAll { rig in
            guard let proxy = rig.proxy, proxy.scene != nil, let parent = proxy.parent else {
                rig.pitch.removeFromParentNode()
                return true
            }
            let p = sk.convert(proxy.position, from: parent)
            rig.pitch.position = v3(p.x, p.y, 0)
            rig.pitch.isHidden = proxy.isHidden || parent.isHidden
            rig.pitch.opacity = proxy.alpha
            rig.roll.scale = v3(proxy.xScale, proxy.yScale, proxy.xScale)
            rig.roll.eulerAngles = v3(0, 0, proxy.zRotation)
            return false
        }
    }

    private func addProp(proxy: SKNode, model: SCNNode) {
        let pitch = SCNNode()
        pitch.eulerAngles = v3(SnowTuning.pitch3D, 0, 0)
        let roll = SCNNode()
        pitch.addChildNode(roll)
        roll.addChildNode(model)
        content.addChildNode(pitch)
        rigs.append(Rig(pitch: pitch, roll: roll, lights: nil, proxy: proxy))
    }

    func addSnowman(proxy: SKNode) {
        addProp(proxy: proxy, model: makeSnowmanModel())
    }

    func addBall(proxy: SKNode, radius: CGFloat) {
        addProp(proxy: proxy, model: makeBallModel(radius: radius))
    }

    func addPiece(proxy: SKNode, kind: PieceKind) {
        addProp(proxy: proxy, model: makePieceModel(kind))
    }

    // MARK: - Ёлки

    func addTree(proxy: SKNode, height h: CGFloat) {
        let pitch = SCNNode()
        pitch.eulerAngles = v3(SnowTuning.pitch3D, 0, 0)
        let roll = SCNNode()
        pitch.addChildNode(roll)

        let brown = material(NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.17, alpha: 1))
        let green = material(NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.24, alpha: 1))
        let white = material(NSColor(calibratedWhite: 0.97, alpha: 1))

        let trunkH = h * 0.14
        let trunkGeo = SCNCylinder(radius: h * 0.045, height: trunkH)
        trunkGeo.radialSegmentCount = 12
        trunkGeo.firstMaterial = brown
        let trunk = SCNNode(geometry: trunkGeo)
        trunk.position = v3(0, trunkH / 2, 0)
        roll.addChildNode(trunk)

        // Ярусы: основание, высота, радиус (доли высоты ёлки)
        let tiers: [(CGFloat, CGFloat, CGFloat)] = [(0.10, 0.42, 0.35), (0.30, 0.38, 0.28), (0.52, 0.48, 0.20)]
        let lights = SCNNode()
        lights.isHidden = true
        let lightColors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.35, green: 0.80, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.45, green: 1.0, blue: 0.50, alpha: 1)
        ]
        let fractions: [CGFloat] = [0.18, 0.40, 0.62, 0.82]
        var colorIndex = 0

        for (k, tier) in tiers.enumerated() {
            let base = tier.0 * h
            let th = tier.1 * h
            let rad = tier.2 * h

            let coneGeo = SCNCone(topRadius: 0, bottomRadius: rad, height: th)
            coneGeo.radialSegmentCount = 24
            coneGeo.firstMaterial = green
            let coneNode = SCNNode(geometry: coneGeo)
            coneNode.position = v3(0, base + th / 2, 0)
            roll.addChildNode(coneNode)

            // Снежная шапка: такая же вершина, чуть шире ёлки
            let capH = th * 0.55
            let extra = th * 0.04
            let capGeo = SCNCone(topRadius: 0, bottomRadius: rad * (capH / th) * 1.18, height: capH + extra)
            capGeo.radialSegmentCount = 24
            capGeo.firstMaterial = white
            let cap = SCNNode(geometry: capGeo)
            cap.position = v3(0, base + th + extra / 2 - capH / 2, 0)
            roll.addChildNode(cap)

            // Огоньки по поверхности яруса
            for (j, f) in fractions.enumerated() {
                let angle = CGFloat(k) * 0.9 + CGFloat(j) * 1.7
                let ringR = rad * (1 - f) * 1.05
                let sphereGeo = SCNSphere(radius: max(1.0, h * 0.035))
                sphereGeo.segmentCount = 8
                let m = SCNMaterial()
                m.lightingModel = .constant
                let color = lightColors[colorIndex % lightColors.count]
                m.diffuse.contents = color
                m.emission.contents = color
                sphereGeo.firstMaterial = m
                let bulb = SCNNode(geometry: sphereGeo)
                bulb.position = v3(ringR * cos(angle), base + f * th, ringR * sin(angle))
                let d = Double.random(in: 0.35...0.9)
                bulb.runAction(SCNAction.sequence([
                    SCNAction.wait(duration: Double.random(in: 0...0.8)),
                    SCNAction.repeatForever(SCNAction.sequence([
                        SCNAction.fadeOpacity(to: 0.3, duration: d),
                        SCNAction.fadeOpacity(to: 1.0, duration: d)
                    ]))
                ]))
                lights.addChildNode(bulb)
                colorIndex += 1
            }
        }
        roll.addChildNode(lights)
        content.addChildNode(pitch)
        rigs.append(Rig(pitch: pitch, roll: roll, lights: lights, proxy: proxy))
    }

    func setLights(for proxy: SKNode, on: Bool, animated: Bool) {
        for rig in rigs where rig.proxy === proxy {
            guard let lights = rig.lights else { continue }
            if on {
                if lights.isHidden {
                    lights.isHidden = false
                    if animated {
                        lights.opacity = 0
                        lights.runAction(SCNAction.fadeIn(duration: 0.4))
                    } else {
                        lights.opacity = 1
                    }
                }
            } else {
                lights.isHidden = true
            }
        }
    }

    // MARK: - Материалы и заготовки

    private func material(_ color: NSColor, shine: CGFloat = 0.2) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = NSColor(white: shine, alpha: 1)
        m.shininess = 0.3
        return m
    }

    /// Тёплый кремовый снег: как на рисунке, с лёгкой лавандовой тенью от освещения
    private func snowMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.94, alpha: 1)
        m.emission.contents = NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.12, alpha: 1)
        return m
    }

    /// Полупрозрачное стекло: не пишет в буфер глубины, поэтому водителя видно насквозь
    private func glassMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = NSColor(calibratedRed: 0.70, green: 0.88, blue: 1.0, alpha: 1)
        m.specular.contents = NSColor(white: 0.9, alpha: 1)
        m.transparency = 0.35
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ chamfer: CGFloat, _ color: NSColor) -> SCNNode {
        let geo = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        geo.firstMaterial = material(color)
        return SCNNode(geometry: geo)
    }

    private func ball(_ r: CGFloat, _ color: NSColor, glow: Bool = false) -> SCNNode {
        let geo = SCNSphere(radius: r)
        geo.segmentCount = 14
        if glow {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = color
            m.emission.contents = color
            geo.firstMaterial = m
        } else {
            geo.firstMaterial = material(color)
        }
        return SCNNode(geometry: geo)
    }

    private func cone(_ r: CGFloat, _ h: CGFloat, _ color: NSColor) -> SCNNode {
        let geo = SCNCone(topRadius: 0, bottomRadius: r, height: h)
        geo.radialSegmentCount = 14
        geo.firstMaterial = material(color)
        return SCNNode(geometry: geo)
    }

    private func cylinder(_ r: CGFloat, _ h: CGFloat, _ color: NSColor, segments: Int = 12) -> SCNNode {
        let geo = SCNCylinder(radius: r, height: h)
        geo.radialSegmentCount = segments
        geo.firstMaterial = material(color)
        return SCNNode(geometry: geo)
    }

    // MARK: - Снеговик

    /// Колпак Деда Мороза с меховой оторочкой и помпоном. Начало координат в центре головы
    /// радиуса R, колпак слегка завален вперёд-вправо, как на рисунке.
    private func makeSantaHat(headRadius R: CGFloat) -> SCNNode {
        let k = R / 5.2
        let root = SCNNode()
        let red = material(NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.17, alpha: 1), shine: 0.1)
        let fur = material(NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.97, alpha: 1), shine: 0.05)

        let brimY = 0.55 * R
        let brimR = (R * R - brimY * brimY).squareRoot() + 0.15 * k

        let torus = SCNTorus(ringRadius: brimR, pipeRadius: 1.15 * k)
        torus.ringSegmentCount = 28
        torus.pipeSegmentCount = 12
        torus.firstMaterial = fur
        let brim = SCNNode(geometry: torus)
        brim.position = v3(0, brimY, 0)
        brim.eulerAngles = v3(0.12, 0, -0.06)
        root.addChildNode(brim)

        let pivot = SCNNode()
        pivot.position = v3(0, brimY - 0.3 * k, 0)
        pivot.eulerAngles = v3(0, 0, -0.38)
        root.addChildNode(pivot)

        let coneGeo = SCNCone(topRadius: 0.4 * k, bottomRadius: brimR + 0.5 * k, height: 8.4 * k)
        coneGeo.radialSegmentCount = 24
        coneGeo.firstMaterial = red
        let hatCone = SCNNode(geometry: coneGeo)
        hatCone.position = v3(0, 4.2 * k, 0)
        pivot.addChildNode(hatCone)

        let pompGeo = SCNSphere(radius: 1.35 * k)
        pompGeo.segmentCount = 14
        pompGeo.firstMaterial = fur
        let pomp = SCNNode(geometry: pompGeo)
        pomp.position = v3(0, 8.6 * k, 0)
        pivot.addChildNode(pomp)

        return root
    }

    /// Снеговик как на рисунке: три шара, колпак Деда Мороза, чёрные глазки-овалы, морковка,
    /// улыбка из пяти точек, красный шарф с хвостом и руки-веточки с развилками.
    /// Начало координат на земле под центром нижнего шара.
    private func makeSnowmanModel() -> SCNNode {
        let model = SCNNode()
        let snow = snowMaterial()
        let radii = SnowScene.radii
        let centers = SnowScene.textureCenters

        for i in 0..<3 {
            let geo = SCNSphere(radius: radii[i])
            geo.segmentCount = 28
            geo.firstMaterial = snow
            let n = SCNNode(geometry: geo)
            n.position = v3(0, centers[i], 0)
            model.addChildNode(n)
        }

        // Руки-веточки: основная ветка и две развилки
        let twigMat = material(NSColor(calibratedRed: 0.45, green: 0.29, blue: 0.16, alpha: 1), shine: 0.05)
        func twig(_ length: CGFloat, _ radius: CGFloat) -> SCNNode {
            let pivot = SCNNode()
            let geo = SCNCylinder(radius: radius, height: length)
            geo.radialSegmentCount = 8
            geo.firstMaterial = twigMat
            let rod = SCNNode(geometry: geo)
            rod.position = v3(0, length / 2, 0)
            pivot.addChildNode(rod)
            return pivot
        }
        let armSides: [CGFloat] = [-1, 1]
        for side in armSides {
            let arm = twig(10, 0.42)
            arm.position = v3(side * 5.6, 21.2, 0)
            arm.eulerAngles = v3(0, 0, -side * 0.85)

            let upFork = twig(4.2, 0.3)
            upFork.position = v3(0, 5.4, 0)
            upFork.eulerAngles = v3(0, 0, side * 0.8)
            arm.addChildNode(upFork)

            let outFork = twig(3.2, 0.28)
            outFork.position = v3(0, 7.2, 0)
            outFork.eulerAngles = v3(0, 0, -side * 0.7)
            arm.addChildNode(outFork)

            model.addChildNode(arm)
        }

        // Шарф: повязка на шее и хвост спереди
        let scarfMat = material(NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.21, alpha: 1), shine: 0.1)
        let ringGeo = SCNTorus(ringRadius: 4.0, pipeRadius: 1.35)
        ringGeo.ringSegmentCount = 28
        ringGeo.pipeSegmentCount = 12
        ringGeo.firstMaterial = scarfMat
        let ring = SCNNode(geometry: ringGeo)
        ring.position = v3(0, 24.9, 0)
        ring.scale = v3(1, 0.85, 1)
        ring.eulerAngles = v3(0.1, 0, -0.05)
        model.addChildNode(ring)

        let tailGeo = SCNBox(width: 2.8, height: 7.2, length: 1.0, chamferRadius: 0.4)
        tailGeo.firstMaterial = scarfMat
        let tail = SCNNode(geometry: tailGeo)
        tail.position = v3(3.0, 20.9, 4.9)
        tail.eulerAngles = v3(-0.25, 0, -0.06)
        model.addChildNode(tail)

        // Лицо и колпак на голове
        let R = radii[2]
        let face = SCNNode()
        face.position = v3(0, centers[2], 0)
        model.addChildNode(face)

        let coal = NSColor(calibratedRed: 0.14, green: 0.06, blue: 0.07, alpha: 1)
        let eyeSides: [CGFloat] = [-1, 1]
        for side in eyeSides {
            let ex = side * 1.85
            let ey: CGFloat = 0.8
            let ez = (R * R - ex * ex - ey * ey).squareRoot() - 0.15
            let eye = ball(0.58, coal)
            eye.scale = v3(0.85, 1.25, 0.6)
            eye.position = v3(ex, ey, ez)
            face.addChildNode(eye)
        }

        // Морковка смотрит на зрителя, слегка вниз и влево
        let noseHolder = SCNNode()
        noseHolder.position = v3(0, -0.5, (R * R - 0.25).squareRoot() - 0.4)
        noseHolder.eulerAngles = v3(0.18, -0.35, 0)
        let carrotGeo = SCNCone(topRadius: 0, bottomRadius: 0.75, height: 3.2)
        carrotGeo.radialSegmentCount = 14
        carrotGeo.firstMaterial = material(NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.12, alpha: 1))
        let carrot = SCNNode(geometry: carrotGeo)
        carrot.eulerAngles = v3(CGFloat.pi / 2, 0, 0)
        carrot.position = v3(0, 0, 1.6)
        noseHolder.addChildNode(carrot)
        face.addChildNode(noseHolder)

        // Улыбка из пяти точек
        for k in 0..<5 {
            let u = CGFloat(k - 2) / 2
            let x = u * 2.4
            let y = -2.3 + 0.9 * u * u
            let z = (R * R - x * x - y * y).squareRoot() - 0.1
            let dotNode = ball(0.34, coal)
            dotNode.position = v3(x, y, z)
            face.addChildNode(dotNode)
        }

        face.addChildNode(makeSantaHat(headRadius: R))
        return model
    }

    /// Катящийся шар: снег с лавандовыми вмятинками, чтобы было видно вращение
    private func makeBallModel(radius r: CGFloat) -> SCNNode {
        let node = SCNNode()
        let geo = SCNSphere(radius: r)
        geo.segmentCount = 24
        geo.firstMaterial = snowMaterial()
        node.addChildNode(SCNNode(geometry: geo))

        let spotMat = SCNMaterial()
        spotMat.lightingModel = .lambert
        spotMat.diffuse.contents = NSColor(calibratedRed: 0.80, green: 0.80, blue: 0.93, alpha: 1)
        let dirs: [(CGFloat, CGFloat, CGFloat)] = [
            (0.55, 0.45, 0.70), (-0.5, -0.2, 0.84), (0.1, -0.75, 0.65), (-0.6, 0.55, 0.55)
        ]
        for d in dirs {
            let len = (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
            let spotGeo = SCNSphere(radius: r * 0.17)
            spotGeo.segmentCount = 8
            spotGeo.firstMaterial = spotMat
            let spot = SCNNode(geometry: spotGeo)
            spot.position = v3(d.0 / len * r * 0.97, d.1 / len * r * 0.97, d.2 / len * r * 0.97)
            spot.scale = v3(1, 1, 0.45)
            node.addChildNode(spot)
        }
        return node
    }

    /// Обломки снеговика: морковка, веточка, кусок шарфа и колпак
    private func makePieceModel(_ kind: PieceKind) -> SCNNode {
        switch kind {
        case .carrot:
            let n = cone(0.9, 3.6, NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.12, alpha: 1))
            n.eulerAngles = v3(0, 0, -CGFloat.pi / 2)
            return n
        case .twig:
            let n = cylinder(0.3, 10, NSColor(calibratedRed: 0.45, green: 0.29, blue: 0.16, alpha: 1), segments: 8)
            n.eulerAngles = v3(0, 0, CGFloat.pi / 2)
            return n
        case .scarf:
            return box(6, 1.8, 2.2, 0.5, NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.21, alpha: 1))
        case .hat:
            let root = SCNNode()
            let hat = makeSantaHat(headRadius: 5.2)
            hat.position = v3(0, -(0.55 * 5.2) - 4, 0)
            root.addChildNode(hat)
            return root
        }
    }

    // MARK: - Снегоуборщик

    /// Милая фигурка мини-погрузчика со шнекороторным снегоочистителем, как на фото:
    /// оранжевый пухлый корпус, крупные колёса с протектором и оранжевыми дисками, стеклянная кабина
    /// с водителем-снеговичком, лапы погрузчика по бокам и широкий чёрный снегоочиститель впереди.
    /// На торцах снегоочистителя вращаются шнеки, а наверху качается труба и выбрасывает снег дугой.
    /// Смотрит в +X, начало координат на земле. Передняя грань снегоочистителя в 29 pt впереди
    /// центра, как у прежней техники, поэтому снег он толкает так же.
    private func makePlowRig() -> PlowRig {
        let pitch = SCNNode()
        pitch.eulerAngles = v3(SnowTuning.pitch3D, 0, 0)
        let roll = SCNNode()
        let flip = SCNNode()
        let model = SCNNode()
        pitch.addChildNode(roll)
        roll.addChildNode(flip)
        flip.addChildNode(model)

        let orange = NSColor(calibratedRed: 0.97, green: 0.52, blue: 0.13, alpha: 1)
        let black = NSColor(calibratedWhite: 0.14, alpha: 1)
        let graphite = NSColor(calibratedWhite: 0.26, alpha: 1)
        let steel = NSColor(calibratedWhite: 0.78, alpha: 1)
        let cream = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.94, alpha: 1)
        let amber = NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.10, alpha: 1)
        let lamp = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.60, alpha: 1)
        let glass = glassMaterial()

        let sides: [CGFloat] = [-1, 1]

        // Крупные колёса: чёрная покрышка с рифлением, оранжевый диск и ступица.
        // Крутятся всё время, пока машина на экране.
        let wheelXs: [CGFloat] = [-12, 4]
        let lugCount = 10
        for side in sides {
            for wx in wheelXs {
                let holder = SCNNode()
                holder.eulerAngles = v3(CGFloat.pi / 2, 0, 0) // ось колеса вдоль Z
                holder.position = v3(wx, 7.2, side * 12)

                let spinner = SCNNode()
                spinner.addChildNode(cylinder(6.2, 6, black, segments: 24))
                spinner.addChildNode(cylinder(4.4, 6.6, orange, segments: 18))
                spinner.addChildNode(cylinder(1.8, 7.0, steel, segments: 10))
                for k in 0..<lugCount {
                    let a = CGFloat(k) * CGFloat.pi * 2 / CGFloat(lugCount)
                    let lug = box(2.0, 5.6, 2.2, 0.5, black)
                    lug.position = v3(6.4 * cos(a), 0, 6.4 * sin(a))
                    lug.eulerAngles = v3(0, -a, 0)
                    spinner.addChildNode(lug)
                }
                spinner.runAction(SCNAction.repeatForever(
                    SCNAction.rotateBy(x: 0, y: -CGFloat.pi * 2, z: 0, duration: 1.25)
                ))
                holder.addChildNode(spinner)
                model.addChildNode(holder)
            }
        }

        // Корпус: оранжевая «коробка», чёрная юбка, моторный отсек с решёткой
        let chassis = box(36, 12, 20, 4, orange)
        chassis.position = v3(-6, 13, 0)
        model.addChildNode(chassis)

        let skirt = box(36.4, 2.6, 20.4, 0.6, black)
        skirt.position = v3(-6, 8.6, 0)
        model.addChildNode(skirt)

        let engine = box(14, 8, 19, 3, orange)
        engine.position = v3(-17, 23, 0)
        model.addChildNode(engine)

        let grille = box(10, 1.2, 16, 0.5, black)
        grille.position = v3(-17, 27.3, 0)
        model.addChildNode(grille)

        let tailLightSides: [CGFloat] = [-7, 7]
        for tz in tailLightSides {
            let tailLight = ball(1.1, NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.2, alpha: 1), glow: true)
            tailLight.position = v3(-24.2, 17, tz)
            model.addChildNode(tailLight)
        }

        // Лапы погрузчика по бокам кабины, наклонены вперёд-вниз к навеске
        for side in sides {
            let pivot = SCNNode()
            pivot.position = v3(-6, 26, side * 10.6)
            pivot.eulerAngles = v3(0, 0, -0.55)
            model.addChildNode(pivot)
            let arm = box(25, 4.4, 3.2, 1.4, orange)
            arm.position = v3(12.5, 0, 0)
            pivot.addChildNode(arm)
        }

        // Кабина: сиденье, чёрные стойки, стёкла, графитовая крыша
        let cabX: CGFloat = 1
        let seat = box(14, 1.6, 14, 0.8, black)
        seat.position = v3(cabX, 19.8, 0)
        model.addChildNode(seat)

        for px in [CGFloat(-6), 8] {
            for pz in [CGFloat(-7), 7] {
                let pillar = box(1.4, 16, 1.4, 0.5, black)
                pillar.position = v3(px, 27.5, pz)
                model.addChildNode(pillar)
            }
        }

        let roof = box(16.4, 2.2, 16.6, 1.2, graphite)
        roof.position = v3(cabX, 36.2, 0)
        model.addChildNode(roof)

        func pane(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
            let geo = SCNBox(width: w, height: h, length: l, chamferRadius: 0.2)
            geo.firstMaterial = glass
            let n = SCNNode(geometry: geo)
            n.position = v3(x, y, z)
            model.addChildNode(n)
        }
        pane(0.5, 14, 13, 8.2, 27.5, 0)           // спереди
        pane(0.5, 14, 13, -6.2, 27.5, 0)          // сзади
        pane(13, 14, 0.5, cabX, 27.5, 7.2)        // сбоку к зрителю
        pane(13, 14, 0.5, cabX, 27.5, -7.2)

        // Водитель-снеговичок в колпаке покачивает головой
        let driverBody = ball(2.8, cream)
        driverBody.position = v3(cabX, 23.7, 0)
        model.addChildNode(driverBody)

        let headGroup = SCNNode()
        headGroup.position = v3(cabX, 28.2, 0)
        model.addChildNode(headGroup)
        headGroup.addChildNode(ball(2.6, cream))
        let driverEyeSides: [CGFloat] = [-0.9, 0.9]
        for ez in driverEyeSides {
            let eye = ball(0.45, NSColor(calibratedWhite: 0.1, alpha: 1))
            eye.position = v3(2.3, 0.7, ez)
            headGroup.addChildNode(eye)
        }
        let driverNose = cone(0.5, 2.0, orange)
        driverNose.eulerAngles = v3(0, 0, -CGFloat.pi / 2) // морковка смотрит вперёд
        driverNose.position = v3(3.2, -0.1, 0)
        headGroup.addChildNode(driverNose)
        let driverHat = makeSantaHat(headRadius: 2.6)
        driverHat.eulerAngles = v3(0, -CGFloat.pi / 2, 0)
        headGroup.addChildNode(driverHat)
        let bobUp = SCNAction.move(by: v3(0, 0.5, 0), duration: 0.35)
        let bobDown = SCNAction.move(by: v3(0, -0.5, 0), duration: 0.35)
        bobUp.timingMode = .easeInEaseOut
        bobDown.timingMode = .easeInEaseOut
        headGroup.runAction(SCNAction.repeatForever(SCNAction.sequence([bobUp, bobDown])))

        // Рабочие фары на крыше и мигалка
        let roofLightZs: [CGFloat] = [-4.6, 4.6]
        for lz in roofLightZs {
            let roofLight = ball(1.5, lamp, glow: true)
            roofLight.position = v3(8.8, 37.4, lz)
            model.addChildNode(roofLight)
        }
        let beaconBase = cylinder(1.3, 1.2, black)
        beaconBase.position = v3(-3, 37.9, 0)
        model.addChildNode(beaconBase)
        let beacon = ball(1.6, amber, glow: true)
        beacon.position = v3(-3, 39.1, 0)
        model.addChildNode(beacon)
        beacon.runAction(SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.2, duration: 0.45),
            SCNAction.fadeOpacity(to: 1.0, duration: 0.45)
        ])))

        // Снегоочиститель: плита крепления, широкий чёрный корпус шнека, нижняя режущая кромка.
        // Вся навеска слегка дрожит, как при работе.
        let mount = box(3, 10, 19, 1, black)
        mount.position = v3(15.5, 11.5, 0)
        model.addChildNode(mount)

        let bladePivot = SCNNode()
        bladePivot.position = v3(14, 9.5, 0)
        model.addChildNode(bladePivot)

        let housing = box(16, 14, 27, 4, black)
        housing.position = v3(8, 0, 0)
        bladePivot.addChildNode(housing)

        let hood = box(16.4, 2.6, 27.4, 1.2, graphite)
        hood.position = v3(8, 7.4, 0)
        bladePivot.addChildNode(hood)

        let edge = box(4, 1.6, 27.4, 0.6, steel)
        edge.position = v3(14.5, -7.9, 0)
        bladePivot.addChildNode(edge)

        // Торцы: диск и звезда шнека, которая вращается
        for side in sides {
            let plate = cylinder(7.6, 1.0, graphite, segments: 28)
            plate.eulerAngles = v3(CGFloat.pi / 2, 0, 0) // ось вдоль Z
            plate.position = v3(8, 0, side * 13.8)
            bladePivot.addChildNode(plate)

            let star = SCNNode()
            star.position = v3(8, 0, side * 14.6)
            for k in 0..<3 {
                let bar = box(12.6, 1.4, 0.8, 0.3, steel)
                bar.eulerAngles = v3(0, 0, CGFloat(k) * CGFloat.pi / 3)
                star.addChildNode(bar)
            }
            let hub = ball(1.6, orange)
            hub.scale = v3(1, 1, 0.5)
            star.addChildNode(hub)
            star.runAction(SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: 0, z: CGFloat.pi * 2, duration: 0.7)
            ))
            bladePivot.addChildNode(star)
        }

        // Выбрасывающая труба: поворотный круг, наклонная труба с козырьком.
        // Она медленно качается из стороны в сторону и выбрасывает снег дугой вперёд-вверх.
        let turret = cylinder(4.2, 2.2, black)
        turret.position = v3(6, 8.8, 6.5)
        bladePivot.addChildNode(turret)

        let swivel = SCNNode()
        swivel.position = v3(6, 9.6, 6.5)
        bladePivot.addChildNode(swivel)

        let tilt = SCNNode()
        tilt.eulerAngles = v3(0, 0, -0.30)
        swivel.addChildNode(tilt)

        let tube = cylinder(3.0, 11, black, segments: 16)
        tube.position = v3(0, 5.5, 0)
        tilt.addChildNode(tube)

        let visor = box(7, 1.8, 7, 0.8, black)
        visor.eulerAngles = v3(0, 0, -0.9)
        visor.position = v3(1.5, 11.4, 0)
        tilt.addChildNode(visor)

        let mouth = SCNNode()
        mouth.position = v3(3.4, 11.8, 0)
        tilt.addChildNode(mouth)

        let swingA = SCNAction.rotateTo(x: 0, y: 0.35, z: 0, duration: 2.2, usesShortestUnitArc: true)
        let swingB = SCNAction.rotateTo(x: 0, y: -0.25, z: 0, duration: 2.2, usesShortestUnitArc: true)
        swingA.timingMode = .easeInEaseOut
        swingB.timingMode = .easeInEaseOut
        swivel.runAction(SCNAction.repeatForever(SCNAction.sequence([swingA, swingB])))

        let puffGeo = SCNSphere(radius: 1.2)
        puffGeo.segmentCount = 8
        let puffMat = SCNMaterial()
        puffMat.lightingModel = .constant
        puffMat.diffuse.contents = NSColor(calibratedWhite: 1.0, alpha: 0.95)
        puffGeo.firstMaterial = puffMat
        let puffTemplate = SCNNode(geometry: puffGeo)

        mouth.runAction(SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.wait(duration: 0.08, withRange: 0.05),
            SCNAction.run { node in
                let puff = puffTemplate.clone()
                let sc = CGFloat.random(in: 0.6...1.3)
                puff.scale = v3(sc, sc, sc)
                node.addChildNode(puff)

                let vx = CGFloat.random(in: 20...38)
                let vy = CGFloat.random(in: 26...44)
                let vz = CGFloat.random(in: 2...10)
                let g: CGFloat = 85
                let life: TimeInterval = 0.95
                puff.runAction(SCNAction.sequence([
                    SCNAction.customAction(duration: life) { n, t in
                        n.position = v3(vx * t, vy * t - 0.5 * g * t * t, vz * t)
                        n.opacity = max(0, 1 - t / CGFloat(life))
                    },
                    SCNAction.removeFromParentNode()
                ]))
            }
        ])))

        let shakeA = SCNAction.rotateTo(x: 0, y: 0, z: 0.02, duration: 0.45, usesShortestUnitArc: true)
        let shakeB = SCNAction.rotateTo(x: 0, y: 0, z: -0.02, duration: 0.45, usesShortestUnitArc: true)
        shakeA.timingMode = .easeInEaseOut
        shakeB.timingMode = .easeInEaseOut
        bladePivot.runAction(SCNAction.repeatForever(SCNAction.sequence([shakeA, shakeB])))

        return PlowRig(pitch: pitch, roll: roll, flip: flip)
    }
}
