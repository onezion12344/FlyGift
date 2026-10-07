// FlyModel.swift — procedural 3D fruit-fly body (FlyWire has no body data;
// the connectome drives behavior, the body is modeled) + per-fly behavior.
// Local frame: +Y forward, +Z up, ground at z=0.

import Cocoa
import SceneKit

let SHADOWS_ENABLED = true
let FLY_SCALE: CGFloat = 1.15
let EDGE_MARGIN: CGFloat = 50
let SCARE_RADIUS: CGFloat = 110        // legacy behavior (non-connectome flies) only
let NERVOUS_RADIUS: CGFloat = 240      // legacy behavior only

func rnd(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range) }
func clampf(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }
func angleDiff(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
    var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}
func smoothstep(_ t: CGFloat) -> CGFloat { let x = clampf(t, 0, 1); return x * x * (3 - 2 * x) }

func mat(_ color: NSColor, specular: CGFloat = 0.25, shininess: CGFloat = 0.25) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = color
    m.specular.contents = NSColor(white: specular, alpha: 1)
    m.shininess = shininess
    return m
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("snapshot: failed to encode PNG\n", stderr); exit(1)
    }
    do { try data.write(to: URL(fileURLWithPath: path)) }
    catch { fputs("snapshot: \(error)\n", stderr); exit(1) }
}

func abdomenTexture() -> NSImage {
    let size = NSSize(width: 64, height: 128)
    let img = NSImage(size: size)
    img.lockFocus()
    let base = NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.32, alpha: 1)
    let dark = NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.09, alpha: 1)
    base.setFill()
    NSRect(origin: .zero, size: size).fill()
    dark.setFill()
    NSRect(x: 0, y: 0, width: 64, height: 26).fill()
    NSRect(x: 0, y: 38, width: 64, height: 10).fill()
    NSRect(x: 0, y: 60, width: 64, height: 10).fill()
    NSRect(x: 0, y: 82, width: 64, height: 9).fill()
    img.unlockFocus()
    return img
}

final class Leg {
    let root: SCNNode
    let baseYaw: CGFloat
    let swingSign: CGFloat
    let phase: CGFloat
    let isFront: Bool
    var angle: CGFloat = 0
    var lift: CGFloat = 0

    init(root: SCNNode, baseYaw: CGFloat, swingSign: CGFloat, phase: CGFloat, isFront: Bool) {
        self.root = root; self.baseYaw = baseYaw; self.swingSign = swingSign
        self.phase = phase; self.isFront = isFront
    }

    func apply() {
        root.eulerAngles = SCNVector3(0, -lift, baseYaw + swingSign * angle)
    }
}

struct FlyModel {
    let root: SCNNode
    let legs: [Leg]
    let foldedWings: SCNNode
    let blurWingL: SCNNode
    let blurWingR: SCNNode
    let abdomen: SCNNode
    let realisticSprite: SCNNode?
}

func buildLeg(attach: SCNVector3, baseYaw: CGFloat, swingSign: CGFloat, phase: CGFloat,
              isFront: Bool, femur: CGFloat, tibia: CGFloat, tarsus: CGFloat) -> Leg {
    let legColor = NSColor(calibratedRed: 0.33, green: 0.24, blue: 0.14, alpha: 1)
    let root = SCNNode()
    root.position = attach

    let femurGeo = SCNCapsule(capRadius: 0.48, height: femur)
    femurGeo.materials = [mat(legColor)]
    let femurNode = SCNNode(geometry: femurGeo)
    femurNode.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
    femurNode.position = SCNVector3(femur / 2, 0, 0)
    root.addChildNode(femurNode)

    let knee = SCNNode()
    knee.position = SCNVector3(femur, 0, 0)
    knee.eulerAngles = SCNVector3(0, 0.75, -0.30 * swingSign)
    root.addChildNode(knee)

    let tibiaGeo = SCNCapsule(capRadius: 0.38, height: tibia)
    tibiaGeo.materials = [mat(legColor)]
    let tibiaNode = SCNNode(geometry: tibiaGeo)
    tibiaNode.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
    tibiaNode.position = SCNVector3(tibia / 2, 0, 0)
    knee.addChildNode(tibiaNode)

    let ankle = SCNNode()
    ankle.position = SCNVector3(tibia, 0, 0)
    ankle.eulerAngles = SCNVector3(0, 0.35, -0.15 * swingSign)
    knee.addChildNode(ankle)

    let tarsusGeo = SCNCapsule(capRadius: 0.24, height: tarsus)
    tarsusGeo.materials = [mat(legColor.blended(withFraction: 0.25, of: .black) ?? legColor)]
    let tarsusNode = SCNNode(geometry: tarsusGeo)
    tarsusNode.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
    tarsusNode.position = SCNVector3(tarsus / 2, 0, 0)
    ankle.addChildNode(tarsusNode)

    let leg = Leg(root: root, baseYaw: baseYaw, swingSign: swingSign, phase: phase, isFront: isFront)
    leg.apply()
    return leg
}

func wingShape() -> SCNGeometry {
    let path = NSBezierPath(ovalIn: NSRect(x: -2.6, y: -15.5, width: 5.2, height: 16.5))
    path.flatness = 0.1
    let shape = SCNShape(path: path, extrusionDepth: 0.12)
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = NSColor(calibratedWhite: 0.92, alpha: 0.28)
    m.specular.contents = NSColor(white: 0.9, alpha: 1)
    m.shininess = 0.9
    m.isDoubleSided = true
    shape.materials = [m]
    return shape
}

func realisticFlySprite() -> SCNNode? {
    guard let url = findResource("fly-realistic-v2.png")
            ?? findResource("assets/fly-realistic-v2.png"),
          let image = NSImage(contentsOf: url) else { return nil }
    let plane = SCNPlane(width: 30, height: 31)
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = image
    material.isDoubleSided = true
    material.blendMode = .alpha
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    plane.materials = [material]
    let node = SCNNode(geometry: plane)
    node.name = "realisticFlySprite"
    node.position = SCNVector3(0, 0, 10.5)
    node.renderingOrder = 20
    return node
}

func buildFlyModel() -> FlyModel {
    let root = SCNNode()
    root.name = "flyRoot"
    root.scale = SCNVector3(FLY_SCALE, FLY_SCALE, FLY_SCALE)

    let bodyBrown = NSColor(calibratedRed: 0.50, green: 0.38, blue: 0.22, alpha: 1)

    let thoraxGeo = SCNSphere(radius: 4.6)
    thoraxGeo.materials = [mat(bodyBrown, specular: 0.35, shininess: 0.4)]
    let thorax = SCNNode(geometry: thoraxGeo)
    thorax.position = SCNVector3(0, 2.5, 6.2)
    thorax.scale = SCNVector3(0.95, 1.15, 0.85)
    root.addChildNode(thorax)

    let abdGeo = SCNSphere(radius: 5.0)
    let abdMat = SCNMaterial()
    abdMat.lightingModel = .blinn
    abdMat.diffuse.contents = abdomenTexture()
    abdMat.specular.contents = NSColor(white: 0.3, alpha: 1)
    abdMat.shininess = 0.35
    abdGeo.materials = [abdMat]
    let abdomen = SCNNode(geometry: abdGeo)
    abdomen.position = SCNVector3(0, -6.5, 5.6)
    abdomen.scale = SCNVector3(0.9, 1.5, 0.75)
    root.addChildNode(abdomen)

    let headGeo = SCNSphere(radius: 3.0)
    headGeo.materials = [mat(bodyBrown.blended(withFraction: 0.15, of: .white) ?? bodyBrown)]
    let head = SCNNode(geometry: headGeo)
    head.position = SCNVector3(0, 9.0, 6.0)
    head.scale = SCNVector3(1.0, 0.85, 0.9)
    root.addChildNode(head)

    let eyeGeo = SCNSphere(radius: 2.0)
    eyeGeo.materials = [mat(NSColor(calibratedRed: 0.62, green: 0.10, blue: 0.07, alpha: 1),
                            specular: 0.9, shininess: 0.9)]
    for side in [CGFloat(-1), 1] {
        let eye = SCNNode(geometry: eyeGeo)
        eye.position = SCNVector3(side * 2.1, 9.7, 6.4)
        eye.scale = SCNVector3(0.8, 1.0, 1.15)
        root.addChildNode(eye)
    }

    let antGeo = SCNCapsule(capRadius: 0.16, height: 2.2)
    antGeo.materials = [mat(NSColor(calibratedRed: 0.3, green: 0.22, blue: 0.13, alpha: 1))]
    for side in [CGFloat(-1), 1] {
        let ant = SCNNode(geometry: antGeo)
        ant.position = SCNVector3(side * 0.9, 11.6, 6.3)
        ant.eulerAngles = SCNVector3(-1.15, 0, side * 0.35)
        root.addChildNode(ant)
    }

    let probGeo = SCNCone(topRadius: 0.6, bottomRadius: 0.22, height: 2.4)
    probGeo.materials = [mat(NSColor(calibratedRed: 0.35, green: 0.26, blue: 0.16, alpha: 1))]
    let prob = SCNNode(geometry: probGeo)
    prob.position = SCNVector3(0, 10.4, 4.6)
    prob.eulerAngles = SCNVector3(-0.5, 0, 0)
    root.addChildNode(prob)

    var legs: [Leg] = []
    let z: CGFloat = 4.5
    let specs: [(CGFloat, SCNVector3, CGFloat, CGFloat, Bool, CGFloat, CGFloat, CGFloat)] = [
        ( 1, SCNVector3( 3.1,  5.3, z),  0.95, 0.0, true,  4.2,  4.8, 3.2),
        (-1, SCNVector3(-3.1,  5.3, z),  0.95, 0.5, true,  4.2,  4.8, 3.2),
        ( 1, SCNVector3( 3.7,  2.0, z), -0.10, 0.5, false, 4.8,  5.6, 3.8),
        (-1, SCNVector3(-3.7,  2.0, z), -0.10, 0.0, false, 4.8,  5.6, 3.8),
        ( 1, SCNVector3( 3.3, -1.2, z), -0.95, 0.0, false, 5.8,  7.0, 4.6),
        (-1, SCNVector3(-3.3, -1.2, z), -0.95, 0.5, false, 5.8,  7.0, 4.6),
    ]
    for (side, attach, yawOff, phase, isFront, f, t, ta) in specs {
        let baseYaw: CGFloat = side > 0 ? yawOff : (.pi - yawOff)
        let leg = buildLeg(attach: attach, baseYaw: baseYaw, swingSign: side, phase: phase,
                           isFront: isFront, femur: f, tibia: t, tarsus: ta)
        root.addChildNode(leg.root)
        legs.append(leg)
    }

    let foldedWings = SCNNode()
    for side in [CGFloat(-1), 1] {
        let wing = SCNNode(geometry: wingShape())
        wing.position = SCNVector3(side * 1.6, 0.5, side > 0 ? 7.7 : 7.55)
        wing.eulerAngles = SCNVector3(0, 0, side * 0.13)
        foldedWings.addChildNode(wing)
    }
    root.addChildNode(foldedWings)

    func blurWing(_ side: CGFloat) -> SCNNode {
        let g = SCNSphere(radius: 1.0)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(calibratedWhite: 0.85, alpha: 0.30)
        m.isDoubleSided = true
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(side * 6.0, 1.5, 8.2)
        n.scale = SCNVector3(5.5, 2.4, 0.3)
        n.eulerAngles = SCNVector3(0, 0, side * -0.45)
        n.isHidden = true
        return n
    }
    let bl = blurWing(-1), br = blurWing(1)
    root.addChildNode(bl)
    root.addChildNode(br)

    // At desktop scale a calibrated dorsal specimen reads much more naturally
    // than bare primitives. The procedural body remains as a fallback when the
    // packaged specimen texture cannot be loaded.
    let sprite = realisticFlySprite()
    if let sprite {
        for child in root.childNodes { child.isHidden = true }
        root.addChildNode(sprite)
    }

    return FlyModel(root: root, legs: legs, foldedWings: foldedWings,
                    blurWingL: bl, blurWingR: br, abdomen: abdomen,
                    realisticSprite: sprite)
}

// MARK: - Behavior

final class Fly {
    enum State { case walking, idle, grooming, flying, sleeping }

    let model: FlyModel
    var node: SCNNode { model.root }

    var pos: CGPoint
    var heading: CGFloat = rnd(0...(2 * .pi))
    var speed: CGFloat = 30
    var state: State = .walking
    var stateTimer: CGFloat = rnd(1.5...4)
    var gaitPhase: CGFloat = rnd(0...1)
    var time: CGFloat = rnd(0...100)
    var scareCooldown: CGFloat = 0
    var dartCooldown: CGFloat = 0
    var backwardTimer: CGFloat = 0
    var dartTimer: CGFloat = 0
    var stateAge: CGFloat = 0
    var terrain: [Ledge] = []      // walkable window edges, set by the coordinator
    var windows: [WindowRegion] = []
    var ledge: Ledge?              // currently attached window edge
    var hidingAllowed = false
    private(set) var isHiding = false
    private var hideOrigin = CGPoint.zero
    private var hideTarget = CGPoint.zero
    private var hideAge: CGFloat = 0
    private var hideHold: CGFloat = 0
    private var hideCooldown: CGFloat = 4

    var gaitPhasePublic: CGFloat { gaitPhase }
    var walkingIntensity: CGFloat {
        state == .walking ? clampf(abs(backwardTimer > 0 ? 22 : speed) / 60, 0, 1) : 0
    }

    var flightFrom = CGPoint.zero
    var flightTo = CGPoint.zero
    var flightT: CGFloat = 0
    var flightDur: CGFloat = 1
    var flightAge: CGFloat = 0
    var flightMinimum: CGFloat = 1.4
    var flightMaximum: CGFloat = 5
    var flightSpeed: CGFloat = 260
    private var flightSaccadeTimer: CGFloat = 0
    private var flightTurnImpulse: CGFloat = 0
    private var flightLanding = false
    private var flightEscapeHold: CGFloat = 0
    var flightEffort: CGFloat = 0.6   // set at takeoff: escape=1, casual from arousal
    var effortCurrent: CGFloat = 0.6  // live effort: base + ongoing DNp02/04/11 + arousal
    var alt: CGFloat = 0              // 0 ground .. 1 max altitude
    var pitch: CGFloat = 0            // body pitch while climbing/descending
    var flapPhase: CGFloat = 0
    var wingRaise: CGFloat = 0        // grounded threat posture (escape-DN driven)
    private var brainLive = false
    private var liveArousal: CGFloat = 0
    private var liveWing: CGFloat = 0
    private var liveTurn: CGFloat = 0
    private var liveNervous: CGFloat = 0
    private var exitAfterFlight = false
    private(set) var isJumpscaring = false
    private var jumpscareNear = CGPoint.zero

    var isGrounded: Bool { state != .flying }
    var visualRadius: CGFloat { isJumpscaring ? 120 : 22 * (1 + 0.8 * alt) }
    var isTargetable: Bool { !isHiding && !node.isHidden && node.opacity > 0.8 }

    init(at p: CGPoint) {
        model = buildFlyModel()
        pos = p
        syncNode()
    }

    func syncNode() {
        node.position = SCNVector3(pos.x, pos.y, node.position.z)
        node.eulerAngles = SCNVector3(pitch, 0, heading - .pi / 2)
    }

    func startFlight(bounds: CGSize, awayFrom: CGPoint? = nil, escape: Bool = false,
                     effort: CGFloat? = nil) {
        let originLedgeID = ledge?.id
        isHiding = false
        isJumpscaring = false
        node.opacity = 1
        exitAfterFlight = false
        state = .flying
        ledge = nil
        flightEffort = clampf(effort ?? (escape ? 1.0 : rnd(0.4...0.75)), 0.25, 1)
        effortCurrent = flightEffort
        flapPhase = 0
        wingRaise = 0
        flightFrom = pos
        let hw = bounds.width / 2 - EDGE_MARGIN, hh = bounds.height / 2 - EDGE_MARGIN
        var target = CGPoint.zero
        var chosen = false
        // Casual flights strongly prefer another real window edge. This makes
        // the fly visibly commute between apps instead of teleporting around a
        // single window, while the connectome still decides when it takes off.
        let otherLedges = terrain.filter { $0.id != originLedgeID }
        if !escape, awayFrom == nil, !otherLedges.isEmpty, rnd(0...1) < 0.76 {
            let L = otherLedges[Int.random(in: 0..<otherLedges.count)]
            if L.x1 - L.x0 > 90 {
                target = CGPoint(x: rnd((L.x0 + 25)...(L.x1 - 25)), y: L.y)
                chosen = hypot(target.x - pos.x, target.y - pos.y) > 130
            }
        }
        if !chosen {
            for _ in 0..<16 {
                target = CGPoint(x: rnd(-hw...hw), y: rnd(-hh...hh))
                let far = hypot(target.x - pos.x, target.y - pos.y) > (escape ? 350 : 260)
                if !far { continue }
                if let a = awayFrom {
                    // escape away from the threat: target must be on the far side
                    let toT = CGPoint(x: target.x - pos.x, y: target.y - pos.y)
                    let toA = CGPoint(x: a.x - pos.x, y: a.y - pos.y)
                    if toT.x * toA.x + toT.y * toA.y > 0 { continue }
                }
                break
            }
        }
        flightTo = target
        let dist = hypot(target.x - pos.x, target.y - pos.y)
        // A flight is no longer a one-shot interpolation to `flightTo`.
        // These are a minimum commitment and a safety ceiling; the live brain,
        // threat geometry and terrain decide what happens between them.
        flightMinimum = escape ? clampf(1.15 + dist / 1_200, 1.25, 2.4)
                               : clampf(1.55 + dist / 1_500, 1.7, 3.0)
        flightMaximum = escape ? clampf(2.0 + dist / 260, 3.0, 6.5)
                               : clampf(2.2 + dist / 220, 3.4, 8.0)
        flightDur = flightMaximum
        flightAge = 0
        flightT = 0
        flightLanding = false
        flightEscapeHold = escape ? 0.75 : 0
        flightSaccadeTimer = rnd(0.16...0.44)
        flightTurnImpulse = 0
        flightSpeed = escape ? rnd(470...620) : rnd(245...370)
        let desired = atan2(target.y - pos.y, target.x - pos.x)
        heading += angleDiff(heading, desired) * (escape ? 0.72 : 0.42)
        scareCooldown = escape ? 2.0 : 2.5
        // wings stay visible and beat; blur discs add the motion-smear
        model.blurWingL.isHidden = false
        model.blurWingR.isHidden = false
    }

    func startExitFlight(bounds: CGSize) {
        isHiding = false
        isJumpscaring = false
        node.opacity = 1
        state = .flying
        ledge = nil
        exitAfterFlight = true
        flightEffort = 1.0
        effortCurrent = 1.0
        flapPhase = 0
        wingRaise = 0
        flightFrom = pos
        let side: CGFloat = pos.x >= 0 ? 1 : -1
        flightTo = CGPoint(x: side * (bounds.width / 2 + 220),
                           y: clampf(pos.y + rnd(-140...140), -bounds.height / 2, bounds.height / 2))
        flightT = 0
        flightDur = 1.05
        flightAge = 0
        model.blurWingL.isHidden = false
        model.blurWingR.isHidden = false
    }

    func forceLandingSoon() {
        guard state == .flying, !exitAfterFlight else { return }
        flightLanding = true
        flightMinimum = 0
        flightMaximum = min(flightMaximum, flightAge + 0.9)
        flightTo = CGPoint(x: pos.x + cos(heading) * 90,
                           y: pos.y + sin(heading) * 90)
    }

    func startJumpscare(bounds: CGSize) {
        guard !isJumpscaring, !node.isHidden else { return }
        isHiding = false; node.opacity = 1; ledge = nil
        state = .flying; isJumpscaring = true; exitAfterFlight = false
        flightFrom = pos
        jumpscareNear = CGPoint(x: rnd(-70...70), y: rnd(-35...95))
        let candidates = terrain.filter { hypot($0.y - pos.y, ($0.x0 + $0.x1) / 2 - pos.x) > 180 }
        if let target = candidates.randomElement() {
            flightTo = CGPoint(x: rnd((target.x0 + 24)...(target.x1 - 24)), y: target.y)
        } else {
            flightTo = CGPoint(x: rnd((-bounds.width / 2 + 80)...(bounds.width / 2 - 80)),
                               y: rnd((-bounds.height / 2 + 80)...(bounds.height / 2 - 80)))
        }
        flightT = 0; flightDur = 1.18; flightEffort = 1.2; effortCurrent = 1.2
        flightAge = 0
        flapPhase = 0; wingRaise = 0
    }

    func startHiding(in region: WindowRegion, hold: CGFloat? = nil) {
        guard state != .flying, !isHiding else { return }
        isHiding = true
        state = .idle
        speed = 0
        flightLanding = false
        hideAge = 0
        hideHold = hold ?? rnd(1.1...2.8)
        hideOrigin = pos
        hideTarget = CGPoint(x: clampf(pos.x + rnd(-12...12),
                                       region.rect.minX + 18, region.rect.maxX - 18),
                             y: max(region.rect.minY + 12, region.rect.maxY - 24))
    }

    func finishHidingSoon() {
        guard isHiding else { return }
        hideAge = max(hideAge, 0.32 + hideHold)
    }

    private func updateHiding(dt: CGFloat) {
        hideAge += dt
        let slide: CGFloat = 0.32
        let total = slide * 2 + hideHold
        if hideAge < slide {
            let e = smoothstep(hideAge / slide)
            pos.x = hideOrigin.x + (hideTarget.x - hideOrigin.x) * e
            pos.y = hideOrigin.y + (hideTarget.y - hideOrigin.y) * e
            node.opacity = 1 - e
        } else if hideAge < slide + hideHold {
            pos = hideTarget
            node.opacity = 0
        } else if hideAge < total {
            let e = smoothstep((hideAge - slide - hideHold) / slide)
            pos.x = hideTarget.x + (hideOrigin.x - hideTarget.x) * e
            pos.y = hideTarget.y + (hideOrigin.y - hideTarget.y) * e
            node.opacity = e
        } else {
            pos = hideOrigin
            node.opacity = 1
            isHiding = false
            hideCooldown = rnd(5...10)
            stateTimer = rnd(0.4...1.2)
        }
    }

    private func land() {
        isJumpscaring = false
        state = .idle
        stateTimer = rnd(0.3...0.8)
        // A visible touchdown should be a real opportunity to swing. Without a
        // brief refractory window, a swatter held near the landing point can
        // drive GF on the very next render frame and make the fly appear
        // impossible to hit despite having visibly landed.
        scareCooldown = max(scareCooldown, 0.48)
        speed = 0
        alt = 0
        pitch = 0
        node.scale = SCNVector3(FLY_SCALE, FLY_SCALE, FLY_SCALE)
        var p = node.position; p.z = 0; node.position = p
        // refold the wings flat over the abdomen
        for (i, wing) in model.foldedWings.childNodes.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            wing.eulerAngles = SCNVector3(0, 0, side * 0.13)
        }
        model.blurWingL.isHidden = true
        model.blurWingR.isHidden = true
    }

    private func pickNextState() {
        switch state {
        case .walking:
            let r = rnd(0...1)
            if r < 0.30 { state = .idle; stateTimer = rnd(0.8...3); speed = 0 }
            else if r < 0.55 {
                stateTimer = rnd(0.3...0.8); speed = rnd(95...150)
                heading += rnd(-1.2...1.2)
            } else { stateTimer = rnd(1.5...5); speed = rnd(18...45) }
        case .idle:
            let r = rnd(0...1)
            if r < 0.35 { state = .grooming; stateTimer = rnd(1.0...2.5) }
            else { state = .walking; stateTimer = rnd(1.5...5); speed = rnd(18...45)
                   heading += rnd(-1.5...1.5) }
        case .grooming:
            state = .idle; stateTimer = rnd(0.3...1.0)
        case .flying, .sleeping:
            break
        }
    }

    func update(dt: CGFloat, bounds: CGSize, mouse: CGPoint?, signals: BrainSignals?) {
        time += dt
        scareCooldown = max(0, scareCooldown - dt)
        dartCooldown = max(0, dartCooldown - dt)
        backwardTimer = max(0, backwardTimer - dt)
        hideCooldown = max(0, hideCooldown - dt)

        stateAge += dt
        dartTimer = max(0, dartTimer - dt)

        // live brain drives reach the wings even mid-flight
        brainLive = signals != nil
        liveArousal = signals?.arousal ?? 0
        liveWing = signals?.wingDrive ?? 0
        liveTurn = signals?.turnBias ?? 0
        liveNervous = signals?.nervous ?? 0

        if isHiding {
            // Hiding never masks the real emergency pathway: a Giant Fiber
            // spike still pulls the fly straight out from behind the window.
            if let s = signals, s.escape && scareCooldown == 0 {
                startFlight(bounds: bounds, awayFrom: mouse, escape: true)
            } else {
                updateHiding(dt: dt)
                updateLegs(dt: dt)
                updateWings(dt: dt)
                syncNode()
                return
            }
        }

        if state == .flying {
            flightEscapeHold = max(0, flightEscapeHold - dt)
            if let s = signals, s.escape, flightEscapeHold <= 0.05 {
                flightEscapeHold = 0.85
                flightLanding = false
                flightMinimum = max(flightMinimum, flightAge + 0.8)
                if let m = mouse {
                    let away = atan2(pos.y - m.y, pos.x - m.x)
                    flightTo = CGPoint(x: pos.x + cos(away) * rnd(360...620),
                                       y: pos.y + sin(away) * rnd(360...620))
                    flightTurnImpulse += angleDiff(heading, away) * 0.8
                }
            }
            updateFlight(dt: dt, bounds: bounds, threat: mouse)
        } else if let s = signals {
            brainBehavior(s, dt: dt, bounds: bounds, mouse: mouse)
            if state == .walking { updateWalk(dt: dt, bounds: bounds) }
        } else {
            if scareCooldown == 0, let m = mouse {
                // legacy distance-based fear (extra, brainless flies)
                let mouseDist = hypot(m.x - pos.x, m.y - pos.y)
                if mouseDist < SCARE_RADIUS {
                    startFlight(bounds: bounds, awayFrom: m)
                } else if mouseDist < NERVOUS_RADIUS && state != .walking {
                    setState(.walking)
                    heading = atan2(pos.y - m.y, pos.x - m.x) + rnd(-0.4...0.4)
                    speed = rnd(110...150)
                    stateTimer = rnd(0.4...0.9)
                    scareCooldown = 1.0
                }
            }
            if state != .flying {
                stateTimer -= dt
                if stateTimer <= 0 {
                    if state == .walking && rnd(0...1) < 0.10 { startFlight(bounds: bounds) }
                    else { pickNextState() }
                }
                if state == .walking { updateWalk(dt: dt, bounds: bounds) }
            }
        }

        if hidingAllowed, state != .flying, hideCooldown == 0,
           let attached = ledge,
           let region = windows.first(where: { $0.id == attached.id }),
           stateAge > 0.8, rnd(0...1) < 0.16 * dt {
            startHiding(in: region)
        }

        updateLegs(dt: dt)
        updateWings(dt: dt)
        // slower, deeper breathing while asleep
        let breathe = state == .sleeping ? (1 + 0.05 * sin(time * 1.1))
                                         : (1 + 0.03 * sin(time * 3.0))
        model.abdomen.scale = SCNVector3(0.9, 1.5, 0.75 * breathe)
        syncNode()
    }

    private func setState(_ s: State) {
        guard s != state else { return }
        state = s
        stateAge = 0
    }

    // Every behavioral decision here reads a real neuron population's rate.
    private func brainBehavior(_ s: BrainSignals, dt: CGFloat, bounds: CGSize, mouse: CGPoint?) {
        // Giant fiber spike -> escape takeoff (even startles it out of sleep)
        if s.escape && scareCooldown == 0 {
            startFlight(bounds: bounds, awayFrom: mouse, escape: true)
            return
        }
        // circadian sleep: enter, hold (no walk/groom/dart while asleep), wake to grooming
        if s.sleep {
            if state != .sleeping { setState(.sleeping); speed = 0; dartTimer = 0; backwardTimer = 0 }
            return
        } else if state == .sleeping {
            setState(.grooming)   // flies groom after waking
            return
        }
        // Looming detectors hot but GF quiet -> nervous dart away
        if s.nervous > 0.40 && dartCooldown == 0 {
            ledge = nil
            setState(.walking)
            if let m = mouse {
                heading = atan2(pos.y - m.y, pos.x - m.x) + rnd(-0.4...0.4)
            } else { heading += rnd(-1.5...1.5) }
            speed = rnd(110...155)
            dartTimer = rnd(0.4...0.9)
            dartCooldown = 1.2
        }
        // DNg11 (grooming command) hysteresis
        if state != .walking || dartTimer == 0 {
            if state != .grooming, s.groomDrive > 0.5, s.nervous < 0.3, stateAge > 0.4 {
                setState(.grooming)
            } else if state == .grooming, s.groomDrive < 0.3, stateAge > 0.6 {
                setState(.idle)
            }
        }
        // DNp09 (forward-walking command) hysteresis
        if state == .idle, s.walkDrive > 0.22, stateAge > 0.4 {
            setState(.walking)
            heading += rnd(-0.8...0.8)
        } else if state == .walking, dartTimer == 0, s.walkDrive < 0.08, stateAge > 0.5 {
            setState(.idle)
            speed = 0
        }
        // MDN burst -> backward walk, from any grounded state
        if s.backward && backwardTimer == 0 && dartTimer == 0 {
            if state != .walking { setState(.walking); speed = 0 }
            backwardTimer = 0.5
        }
        // walking speed follows the forward command rate; tempo = temperature
        if state == .walking {
            if dartTimer == 0 && backwardTimer == 0 {
                let target = (14 + s.walkDrive * 55) * s.tempo
                speed += (target - speed) * min(1, 3 * dt)
            }
            if ledge == nil { heading += s.turnBias * dt }   // DNa01/DNa02 steering
        }
        // spontaneous takeoff, gated on whole-population arousal; flight
        // altitude/effort scales with how aroused the network is
        let flightChance: CGFloat = s.arousal > 0.5 ? 0.6 : 0.005
        if state == .walking && rnd(0...1) < flightChance * dt {
            startFlight(bounds: bounds, effort: 0.35 + s.arousal * 0.6)
        }
    }

    private var effectiveSpeed: CGFloat { backwardTimer > 0 ? -22 : speed }

    private func updateWalk(dt: CGFloat, bounds: CGSize) {
        // refresh the attached ledge from current terrain (windows move/close)
        if let L = ledge {
            if let cur = terrain.first(where: { $0.id == L.id }), abs(cur.y - L.y) < 40 {
                ledge = cur
            } else {
                ledge = nil
                startFlight(bounds: bounds)   // the ground vanished from under it
                return
            }
        }
        if let L = ledge {
            // walk along the window edge
            heading += rnd(-1...1) * 0.2 * dt
            let along: CGFloat = cos(heading) >= 0 ? 0 : .pi
            heading += angleDiff(heading, along) * min(1, 6 * dt)
            pos.x += cos(heading) * effectiveSpeed * dt
            pos.y += (L.y - pos.y) * min(1, 10 * dt)
            if pos.x <= L.x0 + 6 && cos(heading) < 0 { heading = 0 }
            if pos.x >= L.x1 - 6 && cos(heading) > 0 { heading = .pi }
            pos.x = clampf(pos.x, L.x0, L.x1)
            if rnd(0...1) < 0.05 * dt { ledge = nil }   // wander off the edge
        } else {
            heading += rnd(-1...1) * 1.6 * dt
            let hw = bounds.width / 2 - EDGE_MARGIN, hh = bounds.height / 2 - EDGE_MARGIN
            if abs(pos.x) > hw || abs(pos.y) > hh {
                let toCenter = atan2(-pos.y, -pos.x)
                heading += angleDiff(heading, toCenter) * min(1, 4 * dt)
            }
            let v = effectiveSpeed
            pos.x += cos(heading) * v * dt
            pos.y += sin(heading) * v * dt
            pos.x = clampf(pos.x, -bounds.width / 2 + 20, bounds.width / 2 - 20)
            pos.y = clampf(pos.y, -bounds.height / 2 + 20, bounds.height / 2 - 20)
            // walked onto a window edge? latch on
            for L in terrain where pos.x > L.x0 - 8 && pos.x < L.x1 + 8 && abs(pos.y - L.y) < 20 {
                ledge = L
                heading = cos(heading) >= 0 ? 0 : .pi
                break
            }
        }
        var p = node.position
        p.z = 0.35 * abs(sin(gaitPhase * .pi * 2))
        node.position = p
    }

    private func applyAltitude() {
        let s = FLY_SCALE * (1 + 0.8 * alt)
        node.scale = SCNVector3(s, s, s)
        var p = node.position
        p.z = 90 * alt
        node.position = p
    }

    private func updateFlight(dt: CGFloat, bounds: CGSize, threat: CGPoint?) {
        if isJumpscaring {
            flightT = min(1, flightT + dt / flightDur)
            updateJumpscareFlight()
            return
        }
        if exitAfterFlight {
            flightT = min(1, flightT + dt / flightDur)
            if flightT >= 1 {
                pos = flightTo
                alt = 1
                node.isHidden = true
                syncNode()
                return
            }
            let e = smoothstep(flightT)
            pos.x = flightFrom.x + (flightTo.x - flightFrom.x) * e
            pos.y = flightFrom.y + (flightTo.y - flightFrom.y) * e
            heading = atan2(flightTo.y - flightFrom.y, flightTo.x - flightFrom.x)
            alt += (1 - alt) * min(1, 8 * dt)
            applyAltitude()
            return
        }

        flightAge += dt
        flightT = min(1, flightAge / max(0.1, flightMaximum))
        effortCurrent = brainLive
            ? clampf(max(flightEffort,
                         flightEffort * 0.55 + liveArousal * 0.25 + liveWing * 0.6), 0.25, 1.3)
            : flightEffort

        let hw = bounds.width / 2 - EDGE_MARGIN
        let hh = bounds.height / 2 - EDGE_MARGIN
        flightTo.x = clampf(flightTo.x, -hw, hw)
        flightTo.y = clampf(flightTo.y, -hh, hh)
        var dx = flightTo.x - pos.x
        var dy = flightTo.y - pos.y
        var distance = max(1, hypot(dx, dy))

        // Reaching a waypoint is not an automatic landing. Under arousal the
        // fly chains another leg, producing a continuous path instead of the
        // old fly-stop-turn cadence.
        if !flightLanding, distance < 72,
           (flightAge < flightMinimum || flightEscapeHold > 0 || liveNervous > 0.34) {
            let bend = rnd(-1.05...1.05) + liveTurn * 0.8
            let leg = rnd(260...520)
            flightTo = CGPoint(x: clampf(pos.x + cos(heading + bend) * leg, -hw, hw),
                               y: clampf(pos.y + sin(heading + bend) * leg, -hh, hh))
            dx = flightTo.x - pos.x; dy = flightTo.y - pos.y
            distance = max(1, hypot(dx, dy))
        }

        let calmEnough = liveNervous < 0.28 && flightEscapeHold <= 0
        if !flightLanding, flightAge >= flightMinimum, distance < 86, calmEnough {
            flightLanding = true
        } else if !flightLanding, flightAge >= flightMaximum {
            flightLanding = true
            flightTo = CGPoint(x: clampf(pos.x + cos(heading) * 105, -hw, hw),
                               y: clampf(pos.y + sin(heading) * 105, -hh, hh))
            dx = flightTo.x - pos.x; dy = flightTo.y - pos.y
            distance = max(1, hypot(dx, dy))
        }

        flightSaccadeTimer -= dt
        if flightSaccadeTimer <= 0, !flightLanding {
            let energy = clampf(liveNervous * 0.75 + liveArousal * 0.2 + liveWing * 0.2, 0, 1)
            flightTurnImpulse += rnd(-1...1) * (0.10 + energy * 0.72)
            flightSaccadeTimer = rnd(0.16...0.42) + (1 - energy) * rnd(0.08...0.28)
        }
        flightTurnImpulse *= exp(-(flightLanding ? 10 : 4.5) * dt)

        var desiredHeading = atan2(dy, dx)
        if !flightLanding { desiredHeading += liveTurn * (0.45 + liveNervous * 0.65) }
        if let threat, !flightLanding {
            let tx = pos.x - threat.x, ty = pos.y - threat.y
            let threatDistance = max(1, hypot(tx, ty))
            let avoidance = clampf(1 - threatDistance / 340, 0, 1)
                * clampf(0.25 + liveNervous + flightEscapeHold, 0, 1.5)
            let away = atan2(ty, tx)
            desiredHeading += angleDiff(desiredHeading, away) * avoidance
        }
        desiredHeading += flightTurnImpulse
        let turnRate = flightLanding ? 10
            : 2.8 + liveNervous * 5.2 + (flightEscapeHold > 0 ? 3.5 : 0)
        heading += clampf(angleDiff(heading, desiredHeading), -turnRate * dt, turnRate * dt)

        let cruise = 210 + effortCurrent * 245 + liveNervous * 150
            + (flightEscapeHold > 0 ? 150 : 0)
        let desiredSpeed = flightLanding ? clampf(distance * 2.8, 18, 210) : cruise
        flightSpeed += (desiredSpeed - flightSpeed) * min(1, (flightLanding ? 4.8 : 2.7) * dt)
        let microWobble = sin(time * 31) * (1.8 + liveNervous * 3.0)
        pos.x += (cos(heading) * flightSpeed - sin(heading) * microWobble) * dt
        pos.y += (sin(heading) * flightSpeed + cos(heading) * microWobble) * dt
        pos.x = clampf(pos.x, -hw, hw); pos.y = clampf(pos.y, -hh, hh)

        let landingProgress = flightLanding ? clampf(1 - distance / 150, 0, 1) : 0
        let cruiseAltitude = clampf(0.48 + effortCurrent * 0.47
                                    + 0.05 * sin(time * 7), 0.35, 1.05)
        let targetAltitude = cruiseAltitude * (1 - landingProgress)
        pitch = clampf((targetAltitude - alt) * 2.5, -0.45, 0.45)
        alt += (targetAltitude - alt) * min(1, (flightLanding ? 7.5 : 5.2) * dt)
        applyAltitude()

        if flightLanding, distance < 24, alt < 0.055 {
            pos = flightTo
            land()
        }
    }

    private func updateJumpscareFlight() {
        if flightT >= 1 {
            pos = flightTo; alt = 0; node.opacity = 1
            land(); return
        }
        let approachEnd: CGFloat = 0.54
        let holdEnd: CGFloat = 0.66
        let scale: CGFloat
        if flightT < approachEnd {
            let e = smoothstep(flightT / approachEnd)
            pos.x = flightFrom.x + (jumpscareNear.x - flightFrom.x) * e
            pos.y = flightFrom.y + (jumpscareNear.y - flightFrom.y) * e
            scale = FLY_SCALE * (1 + 5.6 * e * e)
            heading = atan2(jumpscareNear.y - flightFrom.y, jumpscareNear.x - flightFrom.x) + sin(time * 35) * 0.08
            alt = e
        } else if flightT < holdEnd {
            pos.x = jumpscareNear.x + sin(time * 45) * 5
            pos.y = jumpscareNear.y + cos(time * 39) * 4
            scale = FLY_SCALE * 6.6
            alt = 1
        } else {
            let e = smoothstep((flightT - holdEnd) / (1 - holdEnd))
            pos.x = jumpscareNear.x + (flightTo.x - jumpscareNear.x) * e
            pos.y = jumpscareNear.y + (flightTo.y - jumpscareNear.y) * e
            scale = FLY_SCALE * (6.6 - 5.6 * e)
            heading = atan2(flightTo.y - jumpscareNear.y, flightTo.x - jumpscareNear.x) + sin(time * 26) * 0.08
            alt = 1 - e
        }
        node.scale = SCNVector3(scale, scale, scale)
        var p = node.position; p.z = 165 * alt; node.position = p
    }

    private func updateLegs(dt: CGFloat) {
        let v = abs(effectiveSpeed)
        let walking = (state == .walking && v > 1)
        if walking {
            let amp = clampf(0.20 + v * 0.0022, 0.20, 0.50)
            let stride = max(5, 2 * amp * 13)
            let freq = clampf(v / stride, 3, 11)
            gaitPhase = (gaitPhase + freq * dt).truncatingRemainder(dividingBy: 1)
            let stanceFrac: CGFloat = 0.6
            for leg in model.legs {
                let p = (gaitPhase + leg.phase).truncatingRemainder(dividingBy: 1)
                if p < stanceFrac {
                    leg.angle = amp * (1 - 2 * (p / stanceFrac))
                    leg.lift = 0
                } else {
                    let s = (p - stanceFrac) / (1 - stanceFrac)
                    leg.angle = -amp + 2 * amp * smoothstep(s)
                    leg.lift = sin(s * .pi) * 0.55
                }
                if backwardTimer > 0 { leg.angle = -leg.angle }
                leg.apply()
            }
        } else if state == .grooming {
            for leg in model.legs {
                if leg.isFront {
                    leg.angle = 0.45 + 0.25 * sin(time * 20 + leg.swingSign * 1.3)
                    leg.lift = 0.55 + 0.15 * sin(time * 22)
                } else {
                    leg.angle += (0 - leg.angle) * min(1, 8 * dt)
                    leg.lift += (0 - leg.lift) * min(1, 8 * dt)
                }
                leg.apply()
            }
        } else if state == .flying {
            for leg in model.legs {
                leg.angle += (-0.35 - leg.angle) * min(1, 6 * dt)
                leg.lift += (0.5 - leg.lift) * min(1, 6 * dt)
                leg.apply()
            }
        } else {
            for leg in model.legs {
                leg.angle += (0 - leg.angle) * min(1, 10 * dt)
                leg.lift += (0 - leg.lift) * min(1, 10 * dt)
                leg.apply()
            }
        }
    }

    private func updateWings(dt: CGFloat) {
        guard state == .flying else {
            model.realisticSprite?.scale = SCNVector3(1, 1, 1)
            // grounded threat posture: escape-DN / loom activity raises the wings
            let raiseTarget: CGFloat = (state != .sleeping
                && (liveWing > 0.7 || (brainLive && dartTimer > 0))) ? 1 : 0
            wingRaise += (raiseTarget - wingRaise) * min(1, 8 * dt)
            if wingRaise > 0.01 {
                for (i, wing) in model.foldedWings.childNodes.enumerated() {
                    let side: CGFloat = i == 0 ? -1 : 1
                    wing.eulerAngles = SCNVector3(-0.5 * wingRaise, 0,
                                                  side * (0.13 + 0.3 * wingRaise))
                }
            }
            return
        }
        // visible wing-beat: the wing shapes sweep through a stroke arc,
        // faster when the live effort is higher
        flapPhase = (flapPhase + dt * (14 + 10 * effortCurrent)).truncatingRemainder(dividingBy: 1)
        let stroke = sin(flapPhase * 2 * .pi)
        // A tiny breathing squash preserves the photographic silhouette while
        // giving the high-frequency wing beat a readable shimmer at 30–50 px.
        model.realisticSprite?.scale = SCNVector3(1 + 0.035 * abs(stroke),
                                                  1 - 0.018 * abs(stroke), 1)
        for (i, wing) in model.foldedWings.childNodes.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            wing.eulerAngles = SCNVector3(stroke * 0.35, 0,
                                          side * (0.45 + 0.35 * (0.5 + 0.5 * stroke)))
        }
        let flick = 0.10 + 0.14 * abs(stroke)
        model.blurWingL.opacity = flick
        model.blurWingR.opacity = flick
        model.blurWingL.eulerAngles = SCNVector3(0, 0,  0.45 + stroke * 0.2)
        model.blurWingR.eulerAngles = SCNVector3(0, 0, -0.45 - stroke * 0.2)
    }
}
