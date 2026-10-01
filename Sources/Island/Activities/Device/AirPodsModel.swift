import AppKit
import SceneKit

/// Original, procedurally built 3D AirPods case and earbuds (no Apple artwork is used or copied).
///
/// Choreography modelled on the iPhone connect card:
/// 1. the case floats up into view, lid closed, turning toward the viewer;
/// 2. the lid opens on its hinge with a small overshoot;
/// 3. both earbuds lift out of their wells, one just after the other, and settle;
/// 4. a slow product-shot sway while the card is visible.
enum AirPodsSceneBuilder {
    enum Model { case pro, standard }

    /// - Parameter startDelay: wait before the sequence starts, so it plays once the Island has opened.
    static func make(model: Model, animate: Bool, startDelay: TimeInterval = 0.45) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.15
        addCameraAndLights(to: scene)

        // Real proportions (AirPods Pro case ≈ 60.6 × 45.2 × 21.7 mm); 1 unit ≈ 75 mm.
        let w: CGFloat = model == .pro ? 0.81 : 0.71
        let h: CGFloat = model == .pro ? 0.60 : 0.72
        let d: CGFloat = 0.29
        let lidH = h * 0.27
        let bodyH = h - lidH
        let corner: CGFloat = model == .pro ? 0.20 : 0.17
        let chamfer: CGFloat = 0.075
        let plastic = material(white: 0.97, roughness: 0.28, clearCoat: 0.6)

        let pivot = SCNNode() // entrance + sway
        scene.rootNode.addChildNode(pivot)
        let content = SCNNode()
        content.position = SCNVector3(0, -h * 0.30, 0)
        pivot.addChildNode(content)

        // Body: rounded bottom corners, square top where it meets the lid.
        let body = SCNNode(geometry: extrude(roundedRect(width: w, height: bodyH, top: 0.012, bottom: corner), depth: d, chamfer: chamfer, material: plastic))
        body.position = SCNVector3(0, bodyH / 2, 0)
        content.addChildNode(body)

        // Interior tray, visible once the lid opens.
        let tray = SCNNode(geometry: SCNBox(width: w - 0.07, height: 0.012, length: d - 0.07, chamferRadius: 0.05))
        tray.geometry?.materials = [material(white: 0.78, roughness: 0.55)]
        tray.position = SCNVector3(0, bodyH + 0.001, 0)
        content.addChildNode(tray)

        // Status light on the front.
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .constant
        ledMat.diffuse.contents = NSColor(white: 0.75, alpha: 1)
        let led = SCNNode(geometry: SCNCylinder(radius: 0.011, height: 0.004))
        led.geometry?.materials = [ledMat]
        led.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        led.position = SCNVector3(0, bodyH * 0.55, d / 2 + 0.002)
        content.addChildNode(led)

        // Lid on a hinge along the back-top edge.
        let hinge = SCNNode()
        hinge.position = SCNVector3(0, bodyH, -d / 2 + 0.01)
        content.addChildNode(hinge)
        // The lid is shorter than the case's corner radius, so its corners use the largest valid radius.
        let lid = SCNNode(geometry: extrude(roundedRect(width: w, height: lidH, top: min(corner, lidH - 0.02), bottom: 0.012), depth: d, chamfer: min(chamfer, lidH * 0.3), material: plastic))
        lid.position = SCNVector3(0, lidH / 2, d / 2 - 0.01)
        hinge.addChildNode(lid)

        // Earbuds seated in their wells: stems down, heads above the rim, facing slightly outward.
        let buds: [SCNNode] = [-1.0, 1.0].map { side in
            let bud = earbud(model: model, side: side, material: plastic)
            bud.position = SCNVector3(CGFloat(side) * w * 0.19, bodyH - 0.02, 0.0)
            bud.eulerAngles = SCNVector3(-0.15, CGFloat(side) * 0.35, CGFloat(side) * -0.08)
            content.addChildNode(bud)
            return bud
        }

        let openAngle: CGFloat = -1.9 // ≈ 110°
        guard animate else {
            pivot.eulerAngles = SCNVector3(0.05, 0.32, 0)
            hinge.eulerAngles = SCNVector3(openAngle, 0, 0)
            return scene
        }

        // 1. Enter.
        pivot.eulerAngles = SCNVector3(0.05, -0.9, 0)
        pivot.scale = SCNVector3(0.82, 0.82, 0.82)
        pivot.position = SCNVector3(0, -0.12, 0)
        pivot.opacity = 0
        let enter = SCNAction.group([
            .fadeIn(duration: 0.3),
            .move(to: SCNVector3(0, 0, 0), duration: 0.7),
            .scale(to: 1, duration: 0.7),
            .rotateTo(x: 0.05, y: 0.32, z: 0, duration: 0.95, usesShortestUnitArc: true),
        ])
        enter.timingMode = .easeOut
        // 4. Sway.
        let sway = SCNAction.repeatForever(.sequence([
            .rotateTo(x: 0.05, y: -0.32, z: 0, duration: 3.2, usesShortestUnitArc: true),
            .rotateTo(x: 0.05, y: 0.32, z: 0, duration: 3.2, usesShortestUnitArc: true),
        ]))
        sway.timingMode = .easeInEaseOut
        pivot.runAction(.sequence([.wait(duration: startDelay), enter, sway]))

        // 2. Lid opens with a slight overshoot, then settles.
        let open = SCNAction.rotateTo(x: openAngle - 0.08, y: 0, z: 0, duration: 0.42, usesShortestUnitArc: true)
        open.timingMode = .easeOut
        let settle = SCNAction.rotateTo(x: openAngle, y: 0, z: 0, duration: 0.18, usesShortestUnitArc: true)
        settle.timingMode = .easeInEaseOut
        hinge.runAction(.sequence([.wait(duration: startDelay + 0.5), open, settle]))

        // 3. Earbuds lift out one after the other with a small bounce.
        for (i, bud) in buds.enumerated() {
            bud.position.y -= 0.12
            bud.opacity = 0
            let up = SCNAction.group([.fadeIn(duration: 0.15), .moveBy(x: 0, y: 0.20, z: 0, duration: 0.34)])
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 0.22)
            down.timingMode = .easeInEaseOut
            bud.runAction(.sequence([.wait(duration: startDelay + 0.85 + Double(i) * 0.09), up, down]))
        }
        led.runAction(.sequence([.wait(duration: startDelay + 0.9), .run { n in
            n.geometry?.firstMaterial?.diffuse.contents = NSColor(red: 0.25, green: 0.95, blue: 0.4, alpha: 1)
        }]))
        return scene
    }

    // MARK: Parts

    private static func earbud(model: Model, side: Double, material plastic: SCNMaterial) -> SCNNode {
        let bud = SCNNode()
        let headR: CGFloat = model == .pro ? 0.085 : 0.078
        let head = SCNNode(geometry: SCNSphere(radius: headR))
        head.geometry?.materials = [plastic]
        head.scale = SCNVector3(1.0, 0.92, 1.12)
        bud.addChildNode(head)
        if model == .pro {
            let tip = SCNNode(geometry: SCNCylinder(radius: 0.042, height: 0.05))
            tip.geometry?.materials = [material(white: 0.86, roughness: 0.75)]
            tip.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            tip.position = SCNVector3(CGFloat(side) * -0.03, 0.01, -0.07)
            bud.addChildNode(tip)
        }
        let stemLen: CGFloat = model == .pro ? 0.20 : 0.27
        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.03, height: stemLen))
        stem.geometry?.materials = [plastic]
        stem.position = SCNVector3(0, -stemLen / 2 - 0.02, 0.01)
        bud.addChildNode(stem)
        // Small, subtle sensor mesh on top of the head (a dark front disc reads as cartoon eyes).
        let grille = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.003))
        grille.geometry?.materials = [material(white: 0.45, roughness: 0.7)]
        grille.position = SCNVector3(0, headR * 0.9, -0.01)
        bud.addChildNode(grille)
        return bud
    }

    private static func addCameraAndLights(to scene: SCNScene) {
        // Three-quarter view from slightly above, like product renders.
        let camera = SCNCamera()
        camera.fieldOfView = 20
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.05
        camera.screenSpaceAmbientOcclusionIntensity = 0.9
        camera.screenSpaceAmbientOcclusionRadius = 0.12
        let cam = SCNNode()
        cam.camera = camera
        cam.position = SCNVector3(0, 1.05, 2.45)
        cam.look(at: SCNVector3(0, 0.1, 0))
        scene.rootNode.addChildNode(cam)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, euler: SCNVector3 = SCNVector3Zero, color: NSColor = .white) {
            let n = SCNNode()
            n.light = SCNLight()
            n.light?.type = type
            n.light?.intensity = intensity
            n.light?.color = color
            n.eulerAngles = euler
            scene.rootNode.addChildNode(n)
        }
        light(.directional, 900, euler: SCNVector3(-1.05, -0.6, 0))                                          // key
        light(.directional, 350, euler: SCNVector3(-0.35, 2.6, 0), color: NSColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)) // rim
        light(.ambient, 120)
    }

    private static func material(white: CGFloat, roughness: CGFloat, clearCoat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(white: white, alpha: 1)
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.clearCoat.contents = clearCoat
        m.clearCoatRoughness.contents = 0.12
        return m
    }

    /// Centred rounded rectangle with independent top and bottom corner radii.
    private static func roundedRect(width w: CGFloat, height h: CGFloat, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let x0 = -w / 2, x1 = w / 2, y0 = -h / 2, y1 = h / 2, k: CGFloat = 0.45
        p.move(to: NSPoint(x: x0 + bottom, y: y0))
        p.line(to: NSPoint(x: x1 - bottom, y: y0))
        p.curve(to: NSPoint(x: x1, y: y0 + bottom), controlPoint1: NSPoint(x: x1 - bottom * k, y: y0), controlPoint2: NSPoint(x: x1, y: y0 + bottom * k))
        p.line(to: NSPoint(x: x1, y: y1 - top))
        p.curve(to: NSPoint(x: x1 - top, y: y1), controlPoint1: NSPoint(x: x1, y: y1 - top * k), controlPoint2: NSPoint(x: x1 - top * k, y: y1))
        p.line(to: NSPoint(x: x0 + top, y: y1))
        p.curve(to: NSPoint(x: x0, y: y1 - top), controlPoint1: NSPoint(x: x0 + top * k, y: y1), controlPoint2: NSPoint(x: x0, y: y1 - top * k))
        p.line(to: NSPoint(x: x0, y: y0 + bottom))
        p.curve(to: NSPoint(x: x0 + bottom, y: y0), controlPoint1: NSPoint(x: x0, y: y0 + bottom * k), controlPoint2: NSPoint(x: x0 + bottom * k, y: y0))
        p.close()
        p.flatness = 0.002
        return p
    }

    /// Extrudes a front-profile path along Z with a pillowed (rounded) edge.
    private static func extrude(_ path: NSBezierPath, depth: CGFloat, chamfer: CGFloat, material: SCNMaterial) -> SCNGeometry {
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = chamfer
        shape.chamferMode = .both
        let profile = NSBezierPath()
        profile.move(to: NSPoint(x: 0, y: 1))
        profile.curve(to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.55, y: 1), controlPoint2: NSPoint(x: 1, y: 0.55))
        profile.flatness = 0.01
        shape.chamferProfile = profile
        shape.materials = [material]
        return shape
    }

    /// Studio environment for reflections: bright softbox overhead, darker floor.
    private static func environmentImage() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 256), flipped: false) { rect in
            NSGradient(colorsAndLocations:
                (NSColor(white: 0.08, alpha: 1), 0.0),
                (NSColor(white: 0.35, alpha: 1), 0.42),
                (NSColor(white: 0.95, alpha: 1), 0.62),
                (NSColor(white: 0.55, alpha: 1), 0.8),
                (NSColor(white: 0.85, alpha: 1), 1.0))?.draw(in: rect, angle: 90)
            return true
        }
    }
}
