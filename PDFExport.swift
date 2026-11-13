import UIKit
import simd

/// PDF výkres měření: okótované hrany v metrech, seznam hran, plocha uprostřed obrazce.
enum PDFExport {
    static let pageW: CGFloat = 595, pageH: CGFloat = 842          // A4 v bodech
    static let orange = UIColor(red: 0.94, green: 0.54, blue: 0, alpha: 1)

    static func m(_ v: Float) -> String { "\(MeasureModel.num(v, 2)) m" }
    static func m2(_ v: Float) -> String { "\(MeasureModel.num(v, 2)) m²" }

    static func canExport(_ model: MeasureModel) -> Bool {
        switch model.mode {
        case .area: return model.points.count >= 3
        case .circle: return model.circle != nil
        case .distance: return !model.segments.isEmpty
        }
    }

    static func make(model: MeasureModel, photo: UIImage?) -> URL? {
        let f = DateFormatter(); f.locale = Locale(identifier: "cs_CZ"); f.dateFormat = "d. M. yyyy HH:mm"
        let fileF = DateFormatter(); fileF.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PlochaPro-vykres-\(fileF.string(from: Date())).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let cg = ctx.cgContext
                // hlavička
                UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
                cg.fill(CGRect(x: 0, y: 0, width: pageW, height: 54))
                orange.setFill(); cg.fill(CGRect(x: 0, y: 54, width: pageW, height: 3))
                text("PlochaPro – výkres měření", at: CGPoint(x: 40, y: 17), size: 18, bold: true, color: .white)
                text(f.string(from: Date()), at: CGPoint(x: pageW - 40, y: 21), size: 11, color: .white, align: .right)
                text("Režim: \(model.mode.rawValue)", at: CGPoint(x: 40, y: 72), size: 12, color: .darkGray)

                let box = CGRect(x: 40, y: 95, width: pageW - 80, height: 430)
                cg.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor); cg.setLineWidth(1); cg.stroke(box)

                var rows: [(String, String)] = []
                switch model.mode {
                case .area: rows = drawPolygon(model, in: box.insetBy(dx: 60, dy: 50), cg: cg)
                case .circle: rows = drawCircle(model, in: box.insetBy(dx: 60, dy: 50), cg: cg)
                case .distance: rows = drawSegments(model, in: box.insetBy(dx: 30, dy: 30), cg: cg)
                }

                // tabulka
                var y = box.maxY + 22
                text("Výpis rozměrů", at: CGPoint(x: 40, y: y), size: 14, bold: true); y += 24
                for (i, r) in rows.enumerated() {
                    if y > pageH - 60 { ctx.beginPage(); y = 40 }
                    if i % 2 == 0 { UIColor(white: 0.96, alpha: 1).setFill(); cg.fill(CGRect(x: 40, y: y - 3, width: pageW - 80, height: 19)) }
                    text(r.0, at: CGPoint(x: 48, y: y), size: 11, bold: r.0.hasPrefix("Celkov"))
                    text(r.1, at: CGPoint(x: pageW - 48, y: y), size: 11, bold: r.0.hasPrefix("Celkov"), align: .right)
                    y += 19
                }
                text("Změřeno kamerou iPhonu (AR). Hodnoty jsou orientační – nejde o geodetické zaměření.",
                     at: CGPoint(x: 40, y: pageH - 34), size: 8.5, color: .gray)

                // fotka z měření
                if let img = photo {
                    ctx.beginPage()
                    text("Fotka z měření", at: CGPoint(x: 40, y: 36), size: 16, bold: true)
                    let area = CGRect(x: 40, y: 70, width: pageW - 80, height: pageH - 120)
                    let k = min(area.width / img.size.width, area.height / img.size.height)
                    let w = img.size.width * k, h = img.size.height * k
                    img.draw(in: CGRect(x: area.midX - w / 2, y: area.minY, width: w, height: h))
                }
            }
        } catch { return nil }
        return url
    }

    // MARK: plocha – obrys v rovině bodů
    private static func drawPolygon(_ model: MeasureModel, in rect: CGRect, cg: CGContext) -> [(String, String)] {
        let p3 = model.points
        let n3 = p3.count
        var nrm = SIMD3<Float>(repeating: 0)
        for i in 0..<n3 { nrm += simd_cross(p3[i], p3[(i + 1) % n3]) }
        nrm = simd_length(nrm) > 1e-9 ? simd_normalize(nrm) : SIMD3(0, 1, 0)
        let pts = project(p3, normal: nrm)
        let (T, scale) = fit(pts, in: rect)
        let sp = pts.map(T)

        // výplň a obrys
        let path = UIBezierPath(); path.move(to: sp[0]); sp.dropFirst().forEach { path.addLine(to: $0) }; path.close()
        orange.withAlphaComponent(0.15).setFill(); path.fill()
        UIColor.black.setStroke(); path.lineWidth = 1.6; path.stroke()

        // těžiště obrazce (pro směr kót ven a popisek plochy)
        let c = centroid(sp)
        var rows: [(String, String)] = []
        for i in 0..<n3 {
            let a3 = p3[i], b3 = p3[(i + 1) % n3]
            let len = simd_distance(a3, b3)
            dimension(from: sp[i], to: sp[(i + 1) % n3], away: c, label: "H\(i + 1) = \(m(len))", cg: cg)
            rows.append(("Hrana \(i + 1)" + (i == n3 - 1 && !model.closed ? " (uzavírací)" : ""), m(len)))
        }
        sp.enumerated().forEach { i, p in dot(p, cg: cg); text("\(i + 1)", at: CGPoint(x: p.x + 4, y: p.y - 14), size: 8, color: .darkGray) }
        // plocha uprostřed
        let label = "S = \(m2(model.area))"
        let sz = (label as NSString).size(withAttributes: attrs(16, bold: true))
        UIColor.white.withAlphaComponent(0.9).setFill()
        UIBezierPath(roundedRect: CGRect(x: c.x - sz.width / 2 - 6, y: c.y - sz.height / 2 - 3, width: sz.width + 12, height: sz.height + 6), cornerRadius: 4).fill()
        text(label, at: CGPoint(x: c.x, y: c.y - sz.height / 2), size: 16, bold: true, color: orange, align: .center)
        scaleBar(scale: scale, at: CGPoint(x: rect.minX - 50, y: rect.maxY + 38), cg: cg)

        rows.append(("Obvod", m(model.perimeter + (model.closed ? 0 : simd_distance(p3[n3 - 1], p3[0])))))
        rows.append(("Celková plocha", m2(model.area)))
        return rows
    }

    // MARK: kruh
    private static func drawCircle(_ model: MeasureModel, in rect: CGRect, cg: CGContext) -> [(String, String)] {
        guard let c = model.circle else { return [] }
        let pts = project(model.points + [c.center], normal: c.normal, origin: c.center)
        let r = CGFloat(c.radius)
        let s = min(rect.width, rect.height) / (2 * r)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let T: (CGPoint) -> CGPoint = { CGPoint(x: center.x + $0.x * s, y: center.y - $0.y * s) }
        let circ = UIBezierPath(arcCenter: center, radius: r * s, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        orange.withAlphaComponent(0.15).setFill(); circ.fill()
        UIColor.black.setStroke(); circ.lineWidth = 1.6; circ.stroke()
        pts.dropLast().forEach { dot(T($0), cg: cg) }
        dot(center, cg: cg)
        // průměr (kóta pod kruhem) a poloměr
        let left = CGPoint(x: center.x - r * s, y: center.y), right = CGPoint(x: center.x + r * s, y: center.y)
        dimension(from: left, to: right, away: CGPoint(x: center.x, y: center.y - 1000), label: "Ø = \(m(2 * c.radius))", cg: cg, offset: r * s + 22)
        cg.setStrokeColor(UIColor.darkGray.cgColor); cg.setLineWidth(0.8); cg.setLineDash(phase: 0, lengths: [4, 3])
        cg.move(to: center); cg.addLine(to: CGPoint(x: center.x + r * s * 0.7071, y: center.y - r * s * 0.7071)); cg.strokePath(); cg.setLineDash(phase: 0, lengths: [])
        text("r = \(m(c.radius))", at: CGPoint(x: center.x + r * s * 0.38 + 4, y: center.y - r * s * 0.38 - 16), size: 10, bold: true)
        text("S = \(m2(c.area))", at: CGPoint(x: center.x, y: center.y + 8), size: 16, bold: true, color: orange, align: .center)
        scaleBar(scale: s, at: CGPoint(x: rect.minX - 50, y: rect.maxY + 38), cg: cg)
        return [("Poloměr r", m(c.radius)), ("Průměr Ø", m(2 * c.radius)), ("Obvod", m(c.circumference)),
                ("Počet bodů na obvodu", "\(model.points.count)"), ("Odchylka bodů od kružnice", "±\(m(c.rms))"),
                ("Celková plocha", m2(c.area))]
    }

    // MARK: vzdálenosti – každá úsečka zvlášť
    private static func drawSegments(_ model: MeasureModel, in rect: CGRect, cg: CGContext) -> [(String, String)] {
        let segs = model.segments
        let maxL = CGFloat(segs.map(\.length).max() ?? 1)
        let rowH = min(60, rect.height / CGFloat(max(segs.count, 1)))
        var rows: [(String, String)] = []
        for (i, sgm) in segs.enumerated() {
            let y = rect.minY + rowH * (CGFloat(i) + 0.6)
            let w = (rect.width - 60) * CGFloat(sgm.length) / maxL
            let a = CGPoint(x: rect.minX + 50, y: y), b = CGPoint(x: rect.minX + 50 + w, y: y)
            cg.setStrokeColor(UIColor.black.cgColor); cg.setLineWidth(1.6); cg.move(to: a); cg.addLine(to: b); cg.strokePath()
            dot(a, cg: cg); dot(b, cg: cg)
            text("\(i + 1)", at: CGPoint(x: rect.minX + 20, y: y - 7), size: 11, bold: true)
            text(m(sgm.length), at: CGPoint(x: (a.x + b.x) / 2, y: y - 18), size: 11, bold: true, align: .center)
            rows.append(("Vzdálenost \(i + 1)", m(sgm.length)))
        }
        return rows
    }

    // MARK: pomocné
    /// Body do 2D v rovině s normálou n.
    static func project(_ p: [SIMD3<Float>], normal n: SIMD3<Float>, origin: SIMD3<Float>? = nil) -> [CGPoint] {
        let o = origin ?? p.reduce(SIMD3<Float>(repeating: 0), +) / Float(max(p.count, 1))
        let ref: SIMD3<Float> = abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(0, 0, -1)
        let u = simd_normalize(simd_cross(ref, n)), v = simd_cross(n, u)
        return p.map { q in let d = q - o; return CGPoint(x: CGFloat(simd_dot(d, u)), y: CGFloat(simd_dot(d, v))) }
    }

    static func fit(_ pts: [CGPoint], in rect: CGRect) -> ((CGPoint) -> CGPoint, CGFloat) {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let s = min(rect.width / max(maxX - minX, 0.01), rect.height / max(maxY - minY, 0.01))
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        return ({ CGPoint(x: rect.midX + ($0.x - cx) * s, y: rect.midY - ($0.y - cy) * s) }, s)
    }

    static func centroid(_ p: [CGPoint]) -> CGPoint {
        var a: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
        for i in 0..<p.count {
            let p0 = p[i], p1 = p[(i + 1) % p.count], k = p0.x * p1.y - p1.x * p0.y
            a += k; cx += (p0.x + p1.x) * k; cy += (p0.y + p1.y) * k
        }
        if abs(a) < 1e-6 { let n = CGFloat(p.count); return CGPoint(x: p.map(\.x).reduce(0, +) / n, y: p.map(\.y).reduce(0, +) / n) }
        return CGPoint(x: cx / (3 * a), y: cy / (3 * a))
    }

    /// Kóta: pomocné čáry, kótovací čára s šikmými značkami a popisek, posunutá od obrazce ven.
    static func dimension(from a: CGPoint, to b: CGPoint, away c: CGPoint, label: String, cg: CGContext, offset: CGFloat = 22) {
        let dx = b.x - a.x, dy = b.y - a.y, L = max(hypot(dx, dy), 0.001)
        var nx = -dy / L, ny = dx / L
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        if nx * (mid.x - c.x) + ny * (mid.y - c.y) < 0 { nx = -nx; ny = -ny }   // ven od středu
        let a2 = CGPoint(x: a.x + nx * offset, y: a.y + ny * offset), b2 = CGPoint(x: b.x + nx * offset, y: b.y + ny * offset)
        cg.setStrokeColor(UIColor.darkGray.cgColor); cg.setLineWidth(0.6)
        cg.move(to: CGPoint(x: a.x + nx * 3, y: a.y + ny * 3)); cg.addLine(to: CGPoint(x: a2.x + nx * 5, y: a2.y + ny * 5))
        cg.move(to: CGPoint(x: b.x + nx * 3, y: b.y + ny * 3)); cg.addLine(to: CGPoint(x: b2.x + nx * 5, y: b2.y + ny * 5))
        cg.strokePath()
        cg.setStrokeColor(UIColor.black.cgColor); cg.setLineWidth(0.9)
        cg.move(to: a2); cg.addLine(to: b2); cg.strokePath()
        // šikmé značky (architektonické)
        let tx = (dx / L + nx) * 4, ty = (dy / L + ny) * 4
        cg.setLineWidth(1.4)
        for p in [a2, b2] { cg.move(to: CGPoint(x: p.x - tx, y: p.y - ty)); cg.addLine(to: CGPoint(x: p.x + tx, y: p.y + ty)) }
        cg.strokePath()
        // popisek nad kótou, vždy čitelný (ne vzhůru nohama)
        var ang = atan2(dy, dx); if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
        let mid2 = CGPoint(x: (a2.x + b2.x) / 2 + nx * 2, y: (a2.y + b2.y) / 2 + ny * 2)
        cg.saveGState(); cg.translateBy(x: mid2.x, y: mid2.y); cg.rotate(by: ang)
        let up: CGFloat = (cos(ang) * ny - sin(ang) * nx) < 0 ? -13 : 2     // na vnější stranu kóty
        let sz = (label as NSString).size(withAttributes: attrs(9.5, bold: true))
        UIColor.white.setFill(); cg.fill(CGRect(x: -sz.width / 2 - 2, y: up - 1, width: sz.width + 4, height: sz.height + 1))
        (label as NSString).draw(at: CGPoint(x: -sz.width / 2, y: up - 1), withAttributes: attrs(9.5, bold: true))
        cg.restoreGState()
    }

    static func scaleBar(scale s: CGFloat, at p: CGPoint, cg: CGContext) {
        // měřítko výkresu: 1 bod PDF = 0,3528 mm
        let ratio = 1000 / (s * 0.3528)
        let nice: [CGFloat] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]
        let len = nice.last(where: { $0 * s <= 120 }) ?? 0.1
        cg.setFillColor(UIColor.black.cgColor); cg.fill(CGRect(x: p.x, y: p.y, width: len * s, height: 3))
        text("\(MeasureModel.num(Float(len), len < 1 ? 1 : 0)) m", at: CGPoint(x: p.x + len * s + 6, y: p.y - 5), size: 9)
        text("Měřítko cca 1:\(Int((ratio / 10).rounded() * 10))", at: CGPoint(x: p.x + len * s + 50, y: p.y - 5), size: 9, color: .darkGray)
    }

    static func dot(_ p: CGPoint, cg: CGContext) {
        UIColor.white.setFill(); UIColor.black.setStroke()
        let r = CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)
        cg.fillEllipse(in: r); cg.setLineWidth(1); cg.strokeEllipse(in: r)
    }

    static func attrs(_ size: CGFloat, bold: Bool = false, color: UIColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: color]
    }

    static func text(_ s: String, at p: CGPoint, size: CGFloat, bold: Bool = false, color: UIColor = .black, align: NSTextAlignment = .left) {
        let a = attrs(size, bold: bold, color: color)
        let w = (s as NSString).size(withAttributes: a).width
        let x = align == .right ? p.x - w : align == .center ? p.x - w / 2 : p.x
        (s as NSString).draw(at: CGPoint(x: x, y: p.y), withAttributes: a)
    }
}
