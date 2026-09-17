import Cocoa
import AVFoundation
import SceneKit

enum GiftLanguage {
    case zh, en

    static var systemDefault: GiftLanguage {
        let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return first.hasPrefix("zh") ? .zh : .en
    }

    mutating func toggle() { self = self == .zh ? .en : .zh }
}

struct GiftCopy {
    let language: GiftLanguage

    var giftTitle: String { language == .zh ? "一份给你的礼物" : "A gift for you" }
    var giftBody: String { language == .zh ? "听说你最近缺一个真正实用的东西。" : "We heard you could use something truly practical." }
    var open: String { language == .zh ? "拆开看看" : "Open it" }
    var won: String { language == .zh ? "恭喜，你获得了：" : "Congratulations. You received:" }
    var swatter: String { language == .zh ? "苍蝇拍" : "A fly swatter" }
    var arm: String { language == .zh ? "点击拿起 · 可能马上用得上" : "Pick it up · You may need it soon" }
    var tray: String { language == .zh ? "拿起苍蝇拍" : "Pick up the swatter" }
    var countdownPrefix: String { language == .zh ? "抓住它" : "CATCH IT" }
    var successTitle: String { language == .zh ? "你拍死的，不只是一段动画。" : "You killed more than an animation." }
    var failureTitle: String { language == .zh ? "它用真正的逃逸回路从你手里活下来了。" : "It escaped using a real escape circuit." }
    var science: String {
        language == .zh
            ? "这只果蝇运行着 FlyWire v783 的完整连接组：139,255 个神经元、54,492,922 个突触，以 1 kHz 在 Apple GPU 上模拟。鼠标逼近时会刺激 LC4/LPLC2；Giant Fiber 放电后，它才会起飞。"
            : "This fly ran the complete FlyWire v783 connectome: 139,255 neurons and 54,492,922 synapses simulated at 1 kHz on the Apple GPU. Your approaching cursor stimulated LC4/LPLC2; it took off only when the Giant Fiber fired."
    }
    var boundary: String {
        language == .zh
            ? "连接数据来自真实果蝇；神经生理参数、屏幕感觉转换和身体动作仍是计算模型。"
            : "The wiring data comes from a real fly. Neural physiology, screen sensing, and body motion are still computational models."
    }
    var close: String { language == .zh ? "关闭" : "Close" }
    func successStats(seconds: TimeInterval, swings: Int) -> String {
        language == .zh
            ? String(format: "用时 %.1f 秒 · 挥拍 %d 次", seconds, swings)
            : String(format: "%.1f seconds · %d swings", seconds, swings)
    }
    func failureStats(swings: Int) -> String {
        language == .zh
            ? "它存活了 60 秒 · 挥拍 \(swings) 次"
            : "It survived for 60 seconds · \(swings) swings"
    }
}

enum GamePhase: Equatable {
    case giftClosed, giftOpened, waitingForFly, challenge, killed, escaped, cancelled, reveal, terminated
}

enum ChallengeResult: Equatable {
    case killed(elapsed: TimeInterval, swings: Int)
    case escaped(swings: Int)
    case cancelled
}

struct DoublePressDetector {
    let maximumInterval: TimeInterval
    private(set) var previousPress: TimeInterval?

    init(maximumInterval: TimeInterval = 0.45) { self.maximumInterval = maximumInterval }

    mutating func press(now: TimeInterval) -> Bool {
        defer { previousPress = now }
        guard let previousPress else { return false }
        return now - previousPress <= maximumInterval
    }
}

func flyHitTest(cursor: CGPoint, center: CGPoint, visualRadius: CGFloat,
                forgiveness: CGFloat = 8) -> Bool {
    hypot(cursor.x - center.x, cursor.y - center.y) <= visualRadius + forgiveness
}

final class ChallengeController {
    private(set) var phase: GamePhase = .giftClosed
    private(set) var armed = false
    private(set) var swings = 0
    private(set) var spawnAt: TimeInterval?
    private(set) var startedAt: TimeInterval?
    let duration: TimeInterval

    init(duration: TimeInterval = 60) { self.duration = duration }

    func openGift(now: TimeInterval, delay: TimeInterval) {
        guard phase == .giftClosed else { return }
        phase = .giftOpened
        spawnAt = now + delay
        phase = .waitingForFly
    }

    func arm() { armed = true }
    func recordSwing() { if phase == .challenge && armed { swings += 1 } }

    func shouldSpawn(now: TimeInterval) -> Bool {
        phase == .waitingForFly && now >= (spawnAt ?? .greatestFiniteMagnitude)
    }

    func spawn(now: TimeInterval) {
        guard phase == .waitingForFly else { return }
        startedAt = now
        phase = .challenge
    }

    func remaining(now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return duration }
        return max(0, duration - (now - startedAt))
    }

    func kill(now: TimeInterval) -> ChallengeResult? {
        guard phase == .challenge, armed, let startedAt else { return nil }
        phase = .killed
        return .killed(elapsed: max(0, now - startedAt), swings: swings)
    }

    func tick(now: TimeInterval) -> ChallengeResult? {
        guard phase == .challenge, remaining(now: now) <= 0 else { return nil }
        phase = .escaped
        return .escaped(swings: swings)
    }

    func cancel() -> ChallengeResult? {
        guard phase != .terminated, phase != .cancelled else { return nil }
        phase = .cancelled
        return .cancelled
    }

    func reveal() { if phase == .killed || phase == .escaped { phase = .reveal } }
    func terminate() { phase = .terminated }
}

private let giftCream = NSColor(calibratedRed: 0.91, green: 0.81, blue: 0.62, alpha: 1)
private let giftRed = NSColor(calibratedRed: 0.48, green: 0.07, blue: 0.045, alpha: 1)
private let giftInk = NSColor(calibratedRed: 0.14, green: 0.08, blue: 0.05, alpha: 1)

final class RetroPaperView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        giftCream.setFill(); bounds.fill()
        giftRed.withAlphaComponent(0.10).setFill()
        for y in stride(from: 5, to: Int(bounds.height), by: 9) {
            for x in stride(from: (y / 9) % 2 == 0 ? 5 : 9, to: Int(bounds.width), by: 12) {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(x), y: CGFloat(y), width: 1.2, height: 1.2)).fill()
            }
        }
        giftRed.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 9, dy: 9))
        border.lineWidth = 3; border.stroke()
    }
}

final class SwatterGraphicView: NSView {
    var swing: CGFloat = 0 { didSet { needsDisplay = true } }
    private lazy var swatterImage: NSImage? = {
        guard let url = findResource("swatter-red-v3.png")
                ?? findResource("assets/swatter-red-v3.png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: 10)
        transform.rotate(byDegrees: -10 - swing * 34)
        transform.translateX(by: -bounds.midX, yBy: -10)
        transform.concat()

        if let image = swatterImage {
            let inset = bounds.insetBy(dx: max(2, bounds.width * 0.06),
                                       dy: max(2, bounds.height * 0.025))
            image.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        }

        let plastic = NSColor(calibratedRed: 0.78, green: 0.035, blue: 0.025, alpha: 1)
        let plasticDark = NSColor(calibratedRed: 0.39, green: 0.012, blue: 0.01, alpha: 1)
        let plasticLight = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.12, alpha: 1)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
        shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 1.5, height: -2)
        shadow.set()

        let grip = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 8.5, y: 4, width: 17,
                                                     height: bounds.height * 0.43),
                                xRadius: 8, yRadius: 8)
        NSGradient(starting: plasticLight, ending: plasticDark)?.draw(in: grip, angle: 0)
        plasticDark.setStroke(); grip.lineWidth = 1.4; grip.stroke()
        let handle = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 3.8, y: bounds.height * 0.34,
                                                       width: 7.6, height: bounds.height * 0.28),
                                  xRadius: 3.8, yRadius: 3.8)
        plastic.setFill(); handle.fill(); plasticLight.withAlphaComponent(0.65).setStroke()
        handle.lineWidth = 1; handle.stroke()

        let hole = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 3.2, y: 8, width: 6.4, height: 13),
                                xRadius: 3, yRadius: 3)
        NSColor.black.withAlphaComponent(0.42).setFill(); hole.fill()

        let headRect = NSRect(x: bounds.midX - 34, y: bounds.height * 0.52, width: 68, height: 55)
        let head = NSBezierPath(roundedRect: headRect, xRadius: 7, yRadius: 7)
        NSGradient(starting: plasticLight, ending: plasticDark)?.draw(in: head, angle: -24)
        plasticDark.setStroke(); head.lineWidth = 2.2; head.stroke()

        // Dense square perforations and molded reinforcement ribs match the
        // ubiquitous inexpensive Chinese one-piece plastic swatter.
        let cell: CGFloat = 4.2
        for row in 0..<10 {
            for col in 0..<13 {
                let r = NSRect(x: headRect.minX + 5.3 + CGFloat(col) * cell,
                               y: headRect.minY + 5.0 + CGFloat(row) * cell,
                               width: 2.6, height: 2.6)
                NSColor.black.withAlphaComponent(0.42).setFill()
                NSBezierPath(roundedRect: r, xRadius: 0.6, yRadius: 0.6).fill()
            }
        }
        plasticLight.withAlphaComponent(0.76).setStroke()
        for xEnd in [headRect.minX + 7, headRect.midX, headRect.maxX - 7] {
            let rib = NSBezierPath(); rib.move(to: NSPoint(x: bounds.midX, y: headRect.minY + 1))
            rib.line(to: NSPoint(x: xEnd, y: headRect.maxY - 5)); rib.lineWidth = 2; rib.stroke()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

final class GiftBox3DView: SCNView {
    var onOpen: (() -> Void)?
    private let giftRoot = SCNNode()
    private let lid = SCNNode()
    private var opened = false

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        buildScene()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildScene() {
        let scene = SCNScene(); self.scene = scene
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        allowsCameraControl = false

        let red = SCNMaterial(); red.lightingModel = .physicallyBased
        red.diffuse.contents = NSColor(calibratedRed: 0.50, green: 0.025, blue: 0.02, alpha: 1)
        red.roughness.contents = 0.38; red.metalness.contents = 0.03
        let gold = SCNMaterial(); gold.lightingModel = .physicallyBased
        gold.diffuse.contents = NSColor(calibratedRed: 0.92, green: 0.63, blue: 0.12, alpha: 1)
        gold.roughness.contents = 0.28; gold.metalness.contents = 0.42

        func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat,
                 material: SCNMaterial, bevel: CGFloat) -> SCNNode {
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: bevel)
            geometry.materials = [material]
            return SCNNode(geometry: geometry)
        }

        let base = box(116, 72, 86, material: red, bevel: 5)
        base.position.y = -18; base.castsShadow = true
        giftRoot.addChildNode(base)
        let bandFront = box(17, 74, 88, material: gold, bevel: 1.5)
        bandFront.position.y = -17; giftRoot.addChildNode(bandFront)
        let bandCross = box(118, 74, 15, material: gold, bevel: 1.5)
        bandCross.position.y = -17; giftRoot.addChildNode(bandCross)

        let lidTop = box(126, 16, 96, material: red, bevel: 5)
        lidTop.castsShadow = true; lid.addChildNode(lidTop)
        let lidBandA = box(18, 17.5, 98, material: gold, bevel: 1.2); lid.addChildNode(lidBandA)
        let lidBandB = box(128, 17.5, 16, material: gold, bevel: 1.2); lid.addChildNode(lidBandB)
        lid.position.y = 26

        for side in [-1.0, 1.0] {
            let torus = SCNTorus(ringRadius: 13, pipeRadius: 3.2)
            torus.materials = [gold]
            let loop = SCNNode(geometry: torus)
            loop.position = SCNVector3(CGFloat(side) * 12, 15, 0)
            loop.scale = SCNVector3(1.15, 0.62, 0.72)
            loop.eulerAngles.z = CGFloat(side) * 0.30
            lid.addChildNode(loop)
        }
        let knot = SCNSphere(radius: 5.2); knot.materials = [gold]
        let knotNode = SCNNode(geometry: knot); knotNode.position.y = 14; lid.addChildNode(knotNode)
        giftRoot.addChildNode(lid)
        giftRoot.eulerAngles = SCNVector3(-0.12, -0.42, 0)
        scene.rootNode.addChildNode(giftRoot)

        let camera = SCNCamera(); camera.fieldOfView = 34; camera.zNear = 1; camera.zFar = 800
        let cameraNode = SCNNode(); cameraNode.camera = camera
        cameraNode.position = SCNVector3(145, 105, 205)
        let look = SCNLookAtConstraint(target: giftRoot); look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]; scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight(); key.type = .area; key.intensity = 1050
        key.color = NSColor(calibratedRed: 1, green: 0.84, blue: 0.62, alpha: 1)
        key.areaExtents = SIMD3<Float>(110, 110, 0); key.castsShadow = true; key.shadowRadius = 8
        let keyNode = SCNNode(); keyNode.light = key; keyNode.position = SCNVector3(-90, 130, 150)
        keyNode.constraints = [SCNLookAtConstraint(target: giftRoot)]; scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight(); fill.type = .ambient; fill.intensity = 380
        let fillNode = SCNNode(); fillNode.light = fill; scene.rootNode.addChildNode(fillNode)

        let turn = SCNAction.sequence([.rotateBy(x: 0, y: 0.10, z: 0, duration: 1.7),
                                       .rotateBy(x: 0, y: -0.20, z: 0, duration: 3.4),
                                       .rotateBy(x: 0, y: 0.10, z: 0, duration: 1.7)])
        turn.timingMode = .easeInEaseOut
        giftRoot.runAction(.repeatForever(turn), forKey: "idle")
    }

    override func mouseDown(with event: NSEvent) { openGift() }

    func openGift() {
        guard !opened else { return }
        opened = true
        giftRoot.removeAction(forKey: "idle")
        let lift = SCNAction.group([.moveBy(x: 0, y: 58, z: -26, duration: 0.72),
                                    .rotateBy(x: -0.72, y: 0.18, z: 0.12, duration: 0.72)])
        lift.timingMode = .easeInEaseOut
        lid.runAction(lift)
        giftRoot.runAction(.sequence([.scale(to: 1.04, duration: 0.10),
                                      .scale(to: 0.98, duration: 0.12),
                                      .scale(to: 1.0, duration: 0.16)]))
        onOpen?()
    }
}

final class GiftWindowController: NSWindowController {
    var onOpen: (() -> Void)?
    var onArm: (() -> Void)?
    var onLanguageChange: ((GiftLanguage) -> Void)?
    private(set) var language = GiftLanguage.systemDefault
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let giftName = NSTextField(labelWithString: "")
    private let openButton = NSButton(title: "", target: nil, action: nil)
    private let armButton = NSButton(title: "", target: nil, action: nil)
    private let languageButton = NSButton(title: "中 / EN", target: nil, action: nil)
    private let swatter = SwatterGraphicView(frame: .zero)
    private let giftBox = GiftBox3DView(frame: .zero)
    private var opened = false

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        super.init(window: panel)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let window else { return }
        let root = RetroPaperView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        titleLabel.font = .boldSystemFont(ofSize: 29)
        titleLabel.textColor = giftRed
        titleLabel.alignment = .center
        bodyLabel.font = .systemFont(ofSize: 17)
        bodyLabel.textColor = giftInk
        bodyLabel.alignment = .center
        giftName.font = .boldSystemFont(ofSize: 31)
        giftName.textColor = giftRed
        giftName.alignment = .center
        giftName.isHidden = true
        swatter.isHidden = true
        giftBox.onOpen = { [weak self] in self?.openGift() }
        openButton.bezelStyle = .rounded
        openButton.target = self; openButton.action = #selector(openGift)
        armButton.bezelStyle = .rounded
        armButton.target = self; armButton.action = #selector(arm)
        armButton.isHidden = true
        languageButton.isBordered = false
        languageButton.font = .boldSystemFont(ofSize: 12)
        languageButton.contentTintColor = giftRed
        languageButton.target = self; languageButton.action = #selector(toggleLanguage)

        for v in [titleLabel, bodyLabel, giftName, giftBox, swatter, openButton, armButton, languageButton] {
            v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            languageButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            languageButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 46),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 19),
            bodyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 52),
            bodyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -52),
            giftName.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 11),
            giftName.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            giftName.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            giftBox.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            giftBox.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 5),
            giftBox.widthAnchor.constraint(equalToConstant: 330),
            giftBox.heightAnchor.constraint(equalToConstant: 245),
            swatter.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            swatter.topAnchor.constraint(equalTo: giftName.bottomAnchor, constant: 3),
            swatter.widthAnchor.constraint(equalToConstant: 118),
            swatter.heightAnchor.constraint(equalToConstant: 150),
            openButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            openButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -35),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 155),
            armButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            armButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -38),
            armButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 235),
        ])
        updateCopy()
    }

    func showCentered() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.orderFrontRegardless()
    }

    @objc private func openGift() {
        guard !opened else { return }
        opened = true
        bodyLabel.isHidden = true; openButton.isHidden = true
        titleLabel.stringValue = language == .zh ? "正在拆开…" : "Opening…"
        giftBox.openGift(); onOpen?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) { [weak self] in
            guard let self else { return }
            self.giftBox.isHidden = true
            self.giftName.isHidden = false; self.swatter.isHidden = false; self.armButton.isHidden = false
            self.updateCopy()
        }
    }

    @objc private func arm() { onArm?() }
    @objc private func toggleLanguage() {
        language.toggle(); updateCopy(); onLanguageChange?(language)
    }

    private func updateCopy() {
        let c = GiftCopy(language: language)
        titleLabel.stringValue = opened ? c.won : c.giftTitle
        bodyLabel.stringValue = c.giftBody
        openButton.title = c.open
        giftName.stringValue = c.swatter
        armButton.title = c.arm
    }

    func collapseToTray(on screen: NSScreen) {
        guard let window else { return }
        titleLabel.isHidden = true; bodyLabel.isHidden = true; giftName.isHidden = true
        swatter.isHidden = true; openButton.isHidden = true; languageButton.isHidden = true
        armButton.isHidden = false; armButton.title = GiftCopy(language: language).tray
        let size = NSSize(width: 245, height: 94)
        let f = screen.visibleFrame
        window.setFrame(NSRect(x: f.maxX - size.width - 22, y: f.minY + 22, width: size.width, height: size.height), display: true, animate: true)
    }
}

final class SwatterOverlayController {
    private let panel: NSPanel
    private let graphic: SwatterGraphicView
    private(set) var armed = false
    private var animationTimer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 105, height: 135), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        graphic = SwatterGraphicView(frame: panel.contentView?.bounds ?? .zero)
        graphic.autoresizingMask = [.width, .height]; panel.contentView = graphic
    }

    func arm() {
        guard !armed else { return }
        armed = true
        CGDisplayHideCursor(CGMainDisplayID())
        panel.orderFrontRegardless()
    }

    func move(to point: CGPoint) {
        guard armed else { return }
        panel.setFrameOrigin(NSPoint(x: point.x - 52, y: point.y - 115))
    }

    func swing() {
        guard armed else { return }
        animationTimer?.invalidate()
        let start = ProcessInfo.processInfo.systemUptime
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = (ProcessInfo.processInfo.systemUptime - start) / 0.22
            if t >= 1 { self.graphic.swing = 0; timer.invalidate(); return }
            self.graphic.swing = CGFloat(sin(t * .pi))
        }
    }

    func disarm() {
        animationTimer?.invalidate(); animationTimer = nil
        panel.orderOut(nil)
        guard armed else { return }
        armed = false
        CGDisplayShowCursor(CGMainDisplayID())
    }
}

private final class ClickCatcherView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class FlyHitWindowController {
    private let panel: NSPanel
    private let catcher: ClickCatcherView

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 18, height: 18), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        catcher = ClickCatcherView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        panel.contentView = catcher
    }

    var onClick: (() -> Void)? { didSet { catcher.onClick = onClick } }

    func update(at cursor: CGPoint, active: Bool) {
        if active {
            panel.setFrameOrigin(NSPoint(x: cursor.x - 9, y: cursor.y - 9))
            panel.orderFrontRegardless()
        } else { panel.orderOut(nil) }
    }

    func hide() { panel.orderOut(nil) }
}

final class CountdownWindowController {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = giftRed.withAlphaComponent(0.94)
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.level = .floating
        label.frame = panel.contentView?.bounds.insetBy(dx: 10, dy: 10) ?? .zero
        label.autoresizingMask = [.width, .height]
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        label.textColor = giftCream; label.alignment = .center
        panel.contentView?.addSubview(label)
    }

    func show(seconds: Int, language: GiftLanguage, on screen: NSScreen) {
        label.stringValue = "\(GiftCopy(language: language).countdownPrefix)  00:\(String(format: "%02d", seconds))"
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.maxY - 86))
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}

final class SplatWindowController {
    private let panel: NSPanel
    init(at point: CGPoint) {
        panel = NSPanel(contentRect: NSRect(x: point.x - 50, y: point.y - 40, width: 100, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .screenSaver
        let v = SplatView(frame: NSRect(x: 0, y: 0, width: 100, height: 80)); panel.contentView = v
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}

private final class SplatView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = NSColor(calibratedRed: 0.16, green: 0.08, blue: 0.035, alpha: 0.82)
        dark.setFill()
        NSBezierPath(ovalIn: NSRect(x: 22, y: 22, width: 58, height: 34)).fill()
        for i in 0..<13 {
            let a = CGFloat(i) / 13 * .pi * 2
            let r: CGFloat = i % 3 == 0 ? 42 : 34
            let p = NSPoint(x: 50 + cos(a) * r, y: 40 + sin(a) * r * 0.65)
            NSBezierPath(ovalIn: NSRect(x: p.x - 3, y: p.y - 2, width: 6, height: 4)).fill()
        }
    }
}

final class ResultWindowController: NSWindowController {
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private var onClose: (() -> Void)?

    init(result: ChallengeResult, language: GiftLanguage, onClose: @escaping () -> Void) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 610, height: 500), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.level = .screenSaver
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        self.onClose = onClose
        super.init(window: panel)
        build(result: result, language: language)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(result: ChallengeResult, language: GiftLanguage) {
        guard let window else { return }
        let root = RetroPaperView(frame: window.contentView?.bounds ?? .zero); root.autoresizingMask = [.width, .height]; window.contentView = root
        let c = GiftCopy(language: language)
        let success: Bool
        let stats: String
        switch result {
        case let .killed(elapsed, swings): success = true; stats = c.successStats(seconds: elapsed, swings: swings)
        case let .escaped(swings): success = false; stats = c.failureStats(swings: swings)
        case .cancelled: success = false; stats = ""
        }
        let title = NSTextField(wrappingLabelWithString: success ? c.successTitle : c.failureTitle)
        title.font = .boldSystemFont(ofSize: 27); title.textColor = giftRed; title.alignment = .center
        let stat = NSTextField(labelWithString: stats); stat.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold); stat.textColor = giftInk; stat.alignment = .center
        let science = NSTextField(wrappingLabelWithString: c.science); science.font = .systemFont(ofSize: 16); science.textColor = giftInk
        let boundary = NSTextField(wrappingLabelWithString: c.boundary); boundary.font = .systemFont(ofSize: 13); boundary.textColor = giftInk.withAlphaComponent(0.72)
        let repo = NSTextField(labelWithString: "github.com/ThomasLin070217/FlyGift"); repo.font = .monospacedSystemFont(ofSize: 12, weight: .regular); repo.textColor = giftRed; repo.alignment = .center
        closeButton.title = c.close; closeButton.target = self; closeButton.action = #selector(closeNow)
        for v in [title, stat, science, boundary, repo, closeButton] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 68), title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 42), title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -42),
            stat.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 15), stat.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), stat.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            science.topAnchor.constraint(equalTo: stat.bottomAnchor, constant: 29), science.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 55), science.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -55),
            boundary.topAnchor.constraint(equalTo: science.bottomAnchor, constant: 18), boundary.leadingAnchor.constraint(equalTo: science.leadingAnchor), boundary.trailingAnchor.constraint(equalTo: science.trailingAnchor),
            repo.topAnchor.constraint(equalTo: boundary.bottomAnchor, constant: 24), repo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), repo.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            closeButton.centerXAnchor.constraint(equalTo: root.centerXAnchor), closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -37), closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 130)
        ])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.orderFrontRegardless()
    }
    @objc private func closeNow() { onClose?() }
}

final class FlyAudioController {
    private let engine = AVAudioEngine()
    private let buzz = AVAudioPlayerNode()
    private let swing = AVAudioPlayerNode()
    private let hit = AVAudioPlayerNode()
    private var ready = false
    private(set) var muted = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(buzz); engine.attach(swing); engine.attach(hit)
        engine.connect(buzz, to: engine.mainMixerNode, format: format)
        engine.connect(swing, to: engine.mainMixerNode, format: format)
        engine.connect(hit, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            if let buffer = makeBuzz(format: format) {
                buzz.scheduleBuffer(buffer, at: nil, options: .loops)
                buzz.volume = 0; buzz.play()
            }
            ready = true
        } catch { fputs("audio: \(error)\n", stderr) }
    }

    func setMuted(_ value: Bool) { muted = value; if value { buzz.volume = 0 } }
    func setFlying(_ flying: Bool, pan: Float, close: Bool = false) {
        guard ready else { return }
        buzz.pan = max(-1, min(1, pan))
        buzz.volume = muted ? 0 : (flying ? (close ? 0.42 : 0.13) : 0)
    }
    func playSwing() { playOneShot(on: swing, frequency: 92, duration: 0.12, noisy: true, volume: 0.20) }
    func playHit() { playOneShot(on: hit, frequency: 48, duration: 0.19, noisy: true, volume: 0.32) }
    func stop() { buzz.volume = 0; engine.stop() }

    private func makeBuzz(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        b.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            guard let out = b.floatChannelData?[channel] else { continue }
            for i in 0..<Int(frames) {
                let t = Double(i) / format.sampleRate
                let wobble = 205 + 8 * sin(t * 2 * .pi * 7.3)
                let body = sin(t * 2 * .pi * wobble) * 0.55 + sin(t * 2 * .pi * wobble * 2.03) * 0.20
                let grit = Double.random(in: -1...1) * 0.10
                out[i] = Float((body + grit) * 0.55)
            }
        }
        return b
    }

    private func playOneShot(on node: AVAudioPlayerNode, frequency: Double, duration: Double, noisy: Bool, volume: Float) {
        guard ready, !muted else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        b.frameLength = frames
        for c in 0..<2 {
            guard let out = b.floatChannelData?[c] else { continue }
            for i in 0..<Int(frames) {
                let t = Double(i) / format.sampleRate
                let env = exp(-t * 24)
                let n = noisy ? Double.random(in: -1...1) * 0.65 : 0
                out[i] = Float((sin(t * 2 * .pi * frequency) * 0.45 + n) * env)
            }
        }
        node.stop(); node.volume = volume; node.scheduleBuffer(b); node.play()
    }
}

func runGameTest() {
    var failures = 0
    func check(_ name: String, _ ok: @autoclosure () -> Bool) {
        let pass = ok(); print("\(pass ? "PASS" : "FAIL")  \(name)"); if !pass { failures += 1 }
    }
    let c = ChallengeController()
    c.openGift(now: 10, delay: 4)
    check("gift opens into waiting", c.phase == .waitingForFly)
    check("does not spawn early", !c.shouldSpawn(now: 13.9))
    check("spawns at deadline", c.shouldSpawn(now: 14))
    c.spawn(now: 14)
    check("challenge starts at spawn", c.phase == .challenge && c.remaining(now: 64) == 10)
    check("unarmed cannot kill", c.kill(now: 20) == nil)
    c.arm(); c.recordSwing()
    check("armed grounded result records stats", c.kill(now: 20) == .killed(elapsed: 6, swings: 1))

    let timeout = ChallengeController(); timeout.openGift(now: 0, delay: 3); timeout.spawn(now: 3)
    check("last ten begins at 50 elapsed", timeout.remaining(now: 53) == 10)
    check("timeout waits until sixty", timeout.tick(now: 62.9) == nil)
    check("timeout escapes at sixty", timeout.tick(now: 63) == .escaped(swings: 0))

    let cancel = ChallengeController(); cancel.openGift(now: 0, delay: 3)
    check("cancel is idempotent", cancel.cancel() == .cancelled && cancel.cancel() == nil)

    var escape = DoublePressDetector()
    check("single Escape does not cancel", !escape.press(now: 1.0))
    check("double Escape inside 450 ms cancels", escape.press(now: 1.4))
    check("late second Escape does not cancel", !escape.press(now: 2.0))
    check("hit test includes eight-point forgiveness",
          flyHitTest(cursor: CGPoint(x: 29.5, y: 0), center: .zero, visualRadius: 22))
    check("hit test still rejects clear misses",
          !flyHitTest(cursor: CGPoint(x: 31, y: 0), center: .zero, visualRadius: 22))
    if failures > 0 { fputs("\(failures) GAME TEST FAILURES\n", stderr); exit(1) }
    print("GAME TEST PASS")
}
