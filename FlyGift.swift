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

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: 10)
        transform.rotate(byDegrees: -10 - swing * 34)
        transform.translateX(by: -bounds.midX, yBy: -10)
        transform.concat()

        let handle = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 4, y: 6, width: 8, height: bounds.height * 0.58), xRadius: 4, yRadius: 4)
        giftInk.setFill(); handle.fill()
        let headRect = NSRect(x: bounds.midX - 31, y: bounds.height * 0.48, width: 62, height: 52)
        let head = NSBezierPath(roundedRect: headRect, xRadius: 9, yRadius: 9)
        giftRed.setFill(); head.fill()
        giftCream.withAlphaComponent(0.62).setStroke()
        for i in 1..<6 {
            let x = headRect.minX + CGFloat(i) * headRect.width / 6
            let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: headRect.minY + 5)); p.line(to: NSPoint(x: x, y: headRect.maxY - 5)); p.stroke()
        }
        for i in 1..<5 {
            let y = headRect.minY + CGFloat(i) * headRect.height / 5
            let p = NSBezierPath(); p.move(to: NSPoint(x: headRect.minX + 5, y: y)); p.line(to: NSPoint(x: headRect.maxX - 5, y: y)); p.stroke()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
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
    private var opened = false

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 390),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
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
        openButton.bezelStyle = .rounded
        openButton.target = self; openButton.action = #selector(openGift)
        armButton.bezelStyle = .rounded
        armButton.target = self; armButton.action = #selector(arm)
        armButton.isHidden = true
        languageButton.isBordered = false
        languageButton.font = .boldSystemFont(ofSize: 12)
        languageButton.contentTintColor = giftRed
        languageButton.target = self; languageButton.action = #selector(toggleLanguage)

        for v in [titleLabel, bodyLabel, giftName, swatter, openButton, armButton, languageButton] {
            v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            languageButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            languageButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 69),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 19),
            bodyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 52),
            bodyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -52),
            giftName.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 11),
            giftName.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            giftName.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            swatter.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            swatter.topAnchor.constraint(equalTo: giftName.bottomAnchor, constant: 3),
            swatter.widthAnchor.constraint(equalToConstant: 118),
            swatter.heightAnchor.constraint(equalToConstant: 150),
            openButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            openButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -61),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 155),
            armButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            armButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -38),
            armButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 235),
        ])
        updateCopy()
    }

    func showCentered() {
        window?.center(); showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openGift() {
        guard !opened else { return }
        opened = true
        bodyLabel.isHidden = true; openButton.isHidden = true
        giftName.isHidden = false; swatter.isHidden = false; armButton.isHidden = false
        updateCopy(); onOpen?()
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
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        catcher = ClickCatcherView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        panel.contentView = catcher
    }

    var onClick: (() -> Void)? { didSet { catcher.onClick = onClick } }

    func update(at cursor: CGPoint, active: Bool) {
        if active {
            panel.setFrameOrigin(NSPoint(x: cursor.x - 5, y: cursor.y - 5))
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
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.level = .floating
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

    func show() { window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
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
    func setFlying(_ flying: Bool, pan: Float) {
        guard ready else { return }
        buzz.pan = max(-1, min(1, pan)); buzz.volume = muted ? 0 : (flying ? 0.13 : 0)
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
    if failures > 0 { fputs("\(failures) GAME TEST FAILURES\n", stderr); exit(1) }
    print("GAME TEST PASS")
}
