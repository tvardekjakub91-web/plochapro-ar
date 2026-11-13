import Foundation
import simd

/// Stav měření: body v 3D prostoru (metry), hotové úsečky a plocha.
final class MeasureModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case distance = "Vzdálenost"
        case area = "Plocha"
        case circle = "Kruh"
        var id: String { rawValue }
    }
    /// Kruh proložený body po obvodu (v jejich rovině – podlaha, zeď i šikmá plocha).
    struct Circle3D { var center: SIMD3<Float>; var normal: SIMD3<Float>; var radius: Float; var rms: Float
        var area: Float { .pi * radius * radius }
        var circumference: Float { 2 * .pi * radius } }
    struct Segment { var a: SIMD3<Float>; var b: SIMD3<Float>; var length: Float { simd_distance(a, b) } }

    @Published var mode: Mode = .distance { didSet { if oldValue != mode { clear() } } }
    /// Rozpracované body (u vzdálenosti max. 1, u plochy obrys).
    @Published var points: [SIMD3<Float>] = [] { didSet { onChange?() } }
    /// Hotové vzdálenosti.
    @Published var segments: [Segment] = [] { didSet { onChange?() } }
    /// Plocha je uzavřená.
    @Published var closed = false { didSet { onChange?() } }

    @Published var aimValid = false
    @Published var liveDistance: Float?          // od posledního bodu k zaměřovači
    @Published var status = "Pomalu pohybuj telefonem, ať se najde povrch."

    /// Bod v prostoru pod křížkem uprostřed obrazovky (aktualizuje AR pohled).
    var aim: SIMD3<Float>?
    var onChange: (() -> Void)?
    var snapshot: (() -> Any?)?

    // MARK: akce
    func addPoint() {
        guard let p = aim else { return }
        switch mode {
        case .distance:
            if let first = points.first {
                segments.append(Segment(a: first, b: p))
                points = []
            } else {
                points = [p]
            }
        case .area:
            if closed { return }
            if points.count >= 3, simd_distance(p, points[0]) < 0.03 { closed = true; return }  // trefa do prvního bodu = uzavřít
            points.append(p)
        case .circle:
            points.append(p)
        }
    }

    func undo() {
        switch mode {
        case .distance:
            if !points.isEmpty { points.removeAll() }
            else if let s = segments.popLast() { points = [s.a] }
        case .area:
            if closed { closed = false } else if !points.isEmpty { points.removeLast() }
        case .circle:
            if !points.isEmpty { points.removeLast() }
        }
    }

    func closeArea() { if mode == .area && points.count >= 3 { closed = true } }

    func clear() { points = []; segments = []; closed = false; liveDistance = nil }

    // MARK: výpočty
    /// Obvod obrysu (u uzavřené plochy včetně poslední hrany).
    var perimeter: Float {
        guard points.count >= 2 else { return 0 }
        var s: Float = 0
        for i in 0..<(points.count - 1) { s += simd_distance(points[i], points[i + 1]) }
        if closed { s += simd_distance(points.last!, points[0]) }
        return s
    }

    /// Plocha rovinného mnohoúhelníku v prostoru (Newellova metoda) – funguje na podlaze i na zdi.
    var area: Float {
        guard points.count >= 3 else { return 0 }
        var n = SIMD3<Float>(repeating: 0)
        for i in 0..<points.count { n += simd_cross(points[i], points[(i + 1) % points.count]) }
        return simd_length(n) / 2
    }

    /// Nejmenší čtverce (Kåsa) v rovině bodů. Body můžou být v libovolném pořadí.
    var circle: Circle3D? {
        guard mode == .circle, points.count >= 3 else { return nil }
        let c0 = points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)
        var n = SIMD3<Float>(repeating: 0)
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                var c = simd_cross(points[i] - c0, points[j] - c0)
                if simd_dot(c, n) < 0 { c = -c }
                n += c
            }
        }
        if simd_length(n) < 1e-9 { return nil }
        n = simd_normalize(n)
        let ref: SIMD3<Float> = abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let u = simd_normalize(simd_cross(n, ref)), v = simd_cross(n, u)
        let xy = points.map { p -> (Double, Double) in let d = p - c0; return (Double(simd_dot(d, u)), Double(simd_dot(d, v))) }
        var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sz = 0.0, sxz = 0.0, syz = 0.0
        for (x, y) in xy { let z = x * x + y * y; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; sz += z; sxz += x * z; syz += y * z }
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, Double(xy.count)]], r = [-sxz, -syz, -sz]
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d0 = det(m); if abs(d0) < 1e-12 { return nil }
        var sol = [0.0, 0.0, 0.0]
        for k in 0..<3 {
            var mk = m
            for i in 0..<3 { mk[i][k] = r[i] }
            sol[k] = det(mk) / d0
        }
        let cx = -sol[0] / 2, cy = -sol[1] / 2, rr = cx * cx + cy * cy - sol[2]
        guard rr > 0 else { return nil }
        let rad = rr.squareRoot()
        var se = 0.0
        for (x, y) in xy { let e = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() - rad; se += e * e }
        let rms = (se / Double(xy.count)).squareRoot()
        let center = c0 + u * Float(cx) + v * Float(cy)
        return Circle3D(center: center, normal: n, radius: Float(rad), rms: Float(rms))
    }

    var summary: String {
        var lines = ["PlochaPro AR – měření \(Date().formatted(date: .numeric, time: .shortened))"]
        for (i, s) in segments.enumerated() { lines.append("\(i + 1)) \(Self.len(s.length))") }
        if mode == .area && points.count >= 3 {
            lines.append("Plocha: \(Self.num(area, 2)) m²  ·  obvod \(Self.len(perimeter))\(closed ? "" : " (neuzavřeno)")")
            for i in 0..<(closed ? points.count : points.count - 1) {
                lines.append("  hrana \(i + 1): \(Self.len(simd_distance(points[i], points[(i + 1) % points.count])))")
            }
        }
        if let c = circle {
            lines.append("Kruh: plocha \(Self.num(c.area, 2)) m²  ·  r = \(Self.len(c.radius))  ·  Ø \(Self.len(2 * c.radius))  ·  obvod \(Self.len(c.circumference))")
            lines.append("  bodů: \(points.count), odchylka bodů ±\(Self.len(c.rms))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: formát čísel (česky)
    static func num(_ v: Float, _ d: Int) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "cs_CZ"); f.minimumFractionDigits = d; f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func len(_ m: Float) -> String { m < 1 ? "\(num(m * 100, 1)) cm" : "\(num(m, 2)) m" }
}
