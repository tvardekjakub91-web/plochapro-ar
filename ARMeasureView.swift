import SwiftUI
import ARKit
import SceneKit
import UIKit

/// AR pohled: kamera + nalezené povrchy. Uprostřed je zaměřovač, bod se přidá na místo pod ním.
struct ARMeasureView: UIViewRepresentable {
    @ObservedObject var model: MeasureModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        context.coordinator.view = view
        view.scene.rootNode.addChildNode(context.coordinator.root)
        view.scene.rootNode.addChildNode(context.coordinator.reticle)
        view.scene.rootNode.addChildNode(context.coordinator.liveLine)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // iPhone Pro s LiDARem: přesnější a rychlejší nalezení povrchu
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { config.sceneReconstruction = .mesh }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { config.frameSemantics.insert(.sceneDepth) }
        view.session.run(config)

        // nápověda od Applu „pohybuj telefonem“
        let coach = ARCoachingOverlayView()
        coach.session = view.session
        coach.goal = .anyPlane
        coach.activatesAutomatically = true
        coach.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coach)
        NSLayoutConstraint.activate([
            coach.topAnchor.constraint(equalTo: view.topAnchor), coach.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coach.leadingAnchor.constraint(equalTo: view.leadingAnchor), coach.trailingAnchor.constraint(equalTo: view.trailingAnchor)])

        model.onChange = { [weak coord = context.coordinator] in coord?.rebuild() }
        model.snapshot = { [weak view] in view?.snapshot() }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) { uiView.session.pause() }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let model: MeasureModel
        weak var view: ARSCNView?
        let root = SCNNode()
        let reticle = SCNNode()
        let liveLine = SCNNode()
        private let orange = UIColor(red: 0.94, green: 0.54, blue: 0, alpha: 1)

        init(model: MeasureModel) {
            self.model = model
            super.init()
            let ring = SCNTorus(ringRadius: 0.012, pipeRadius: 0.0015)
            ring.firstMaterial?.diffuse.contents = UIColor.white
            ring.firstMaterial?.lightingModel = .constant
            reticle.geometry = ring
            reticle.isHidden = true
        }

        // MARK: každý snímek – kam míří zaměřovač
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let view = view else { return }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            var hit: ARRaycastResult?
            if let q = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) {
                hit = session.raycast(q).first
            }
            if let h = hit {
                let t = h.worldTransform
                model.aim = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                reticle.simdTransform = t
                reticle.isHidden = false
            } else {
                model.aim = nil
                reticle.isHidden = true
            }
            if model.aimValid != (hit != nil) { model.aimValid = hit != nil }

            // živá čára od posledního bodu
            let last: SIMD3<Float>? = (model.closed || model.mode == .circle) ? nil : model.points.last
            if let a = last, let b = model.aim {
                place(line: liveLine, from: a, to: b, color: UIColor.white.withAlphaComponent(0.85), radius: 0.0012)
                liveLine.isHidden = false
                let d = (simd_distance(a, b) * 1000).rounded() / 1000
                if model.liveDistance != d { model.liveDistance = d }
            } else {
                liveLine.isHidden = true
                if model.liveDistance != nil { model.liveDistance = nil }
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let s: String
            switch camera.trackingState {
            case .normal: s = ""
            case .notAvailable: s = "AR není dostupné."
            case .limited(.excessiveMotion): s = "Pohybuj telefonem pomaleji."
            case .limited(.insufficientFeatures): s = "Málo detailů – namiř na strukturovaný povrch nebo víc světla."
            case .limited(.initializing), .limited(.relocalizing): s = "Pomalu pohybuj telefonem, ať se najde povrch."
            default: s = "Omezené sledování."
            }
            DispatchQueue.main.async { self.model.status = s }
        }

        // MARK: kreslení bodů, čar a popisků
        func rebuild() {
            root.childNodes.forEach { $0.removeFromParentNode() }
            for s in model.segments { addSegment(s.a, s.b, label: MeasureModel.len(s.length)) }
            let pts = model.points
            pts.forEach { addDot($0) }
            if model.mode == .circle {
                if let c = model.circle { addCircle(c) }
                return
            }
            if pts.count >= 2 {
                for i in 0..<(pts.count - 1) { addSegment(pts[i], pts[i + 1], label: MeasureModel.len(simd_distance(pts[i], pts[i + 1]))) }
                if model.closed {
                    addSegment(pts[pts.count - 1], pts[0], label: MeasureModel.len(simd_distance(pts[pts.count - 1], pts[0])))
                    addAreaLabel(pts)
                }
            }
        }

        private func addCircle(_ c: MeasureModel.Circle3D) {
            let ring = SCNTorus(ringRadius: CGFloat(c.radius), pipeRadius: 0.002)
            ring.ringSegmentCount = 96
            ring.firstMaterial?.diffuse.contents = orange
            ring.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: ring)
            n.simdPosition = c.center
            n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: c.normal)   // torus leží v rovině XZ
            root.addChildNode(n)
            // výplň
            let disc = SCNCylinder(radius: CGFloat(c.radius), height: 0.0005)
            disc.radialSegmentCount = 96
            disc.firstMaterial?.diffuse.contents = orange.withAlphaComponent(0.25)
            disc.firstMaterial?.lightingModel = .constant
            disc.firstMaterial?.isDoubleSided = true
            let dn = SCNNode(geometry: disc); dn.simdPosition = c.center; dn.simdOrientation = n.simdOrientation
            root.addChildNode(dn)
            // střed + poloměr k prvnímu bodu
            addDot(c.center)
            if let p0 = model.points.first {
                var dir = p0 - c.center; dir -= simd_dot(dir, c.normal) * c.normal
                if simd_length(dir) > 1e-6 {
                    let edge = c.center + simd_normalize(dir) * c.radius
                    let line = SCNNode(); place(line: line, from: c.center, to: edge, color: .white, radius: 0.0012); root.addChildNode(line)
                    addText("r = \(MeasureModel.len(c.radius))", at: (c.center + edge) / 2 + SIMD3(0, 0.01, 0), size: max(0.012, min(c.radius * 0.08, 0.1)), color: .white)
                }
            }
            addText("\(MeasureModel.num(c.area, 2)) m²", at: c.center + SIMD3(0, 0.03, 0), size: max(0.02, min(c.radius * 0.15, 0.25)), color: orange)
        }

        private func addDot(_ p: SIMD3<Float>) {
            let s = SCNSphere(radius: 0.006)
            s.firstMaterial?.diffuse.contents = UIColor.white
            s.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry: s); n.simdPosition = p; root.addChildNode(n)
        }

        private func addSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, label: String) {
            addDot(a); addDot(b)
            let line = SCNNode(); place(line: line, from: a, to: b, color: orange, radius: 0.002); root.addChildNode(line)
            addText(label, at: (a + b) / 2 + SIMD3(0, 0.01, 0), size: max(0.012, min(simd_distance(a, b) * 0.08, 0.12)), color: orange)
        }

        private func addAreaLabel(_ pts: [SIMD3<Float>]) {
            let c = pts.reduce(SIMD3<Float>(repeating: 0), +) / Float(pts.count)
            let a = model.area
            addText("\(MeasureModel.num(a, 2)) m²", at: c + SIMD3(0, 0.02, 0), size: max(0.02, min(sqrt(a) * 0.12, 0.25)), color: .white)
        }

        private func addText(_ t: String, at p: SIMD3<Float>, size: Float, color: UIColor) {
            let txt = SCNText(string: t, extrusionDepth: 0)
            txt.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            txt.flatness = 0.1
            txt.firstMaterial?.diffuse.contents = color
            txt.firstMaterial?.lightingModel = .constant
            txt.firstMaterial?.readsFromDepthBuffer = false   // popisek vždy navrchu
            let node = SCNNode(geometry: txt)
            let (mn, mx) = txt.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((mx.x + mn.x) / 2, (mx.y + mn.y) / 2, 0)
            let k = size / 10
            node.scale = SCNVector3(k, k, k)
            // podklad pod textem
            let w = CGFloat(mx.x - mn.x) + 4, h = CGFloat(mx.y - mn.y) + 3
            let bg = SCNPlane(width: w, height: h); bg.cornerRadius = h / 4
            bg.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.65)
            bg.firstMaterial?.lightingModel = .constant
            bg.firstMaterial?.readsFromDepthBuffer = false
            let bgNode = SCNNode(geometry: bg)
            bgNode.position = SCNVector3((mx.x + mn.x) / 2, (mx.y + mn.y) / 2, -0.1)
            bgNode.renderingOrder = 10; node.renderingOrder = 11
            node.addChildNode(bgNode)
            let holder = SCNNode(); holder.simdPosition = p
            holder.constraints = [SCNBillboardConstraint()]
            holder.addChildNode(node)
            root.addChildNode(holder)
        }

        func place(line node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor, radius: CGFloat) {
            let len = simd_distance(a, b)
            let cyl = (node.geometry as? SCNCylinder) ?? SCNCylinder(radius: radius, height: 1)
            cyl.radius = radius; cyl.height = CGFloat(max(len, 0.0001))
            cyl.firstMaterial?.diffuse.contents = color
            cyl.firstMaterial?.lightingModel = .constant
            node.geometry = cyl
            node.simdPosition = (a + b) / 2
            let dir = len > 0 ? (b - a) / len : SIMD3<Float>(0, 1, 0)
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)   // válec stojí v ose Y
        }
    }
}
