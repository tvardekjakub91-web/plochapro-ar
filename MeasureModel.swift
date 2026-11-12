import Foundation
import simd

/// Stav měření: body v 3D prostoru (metry), hotové úsečky a plocha.
final class MeasureModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case distance = "Vzdálenost"
        case area = "Plocha"
        var id: String { rawValue }
    }
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
        }
    }

    func undo() {
        switch mode {
        case .distance:
            if !points.isEmpty { points.removeAll() }
            else if let s = segments.popLast() { points = [s.a] }
        case .area:
            if closed { closed = false } else if !points.isEmpty { points.removeLast() }
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

    var summary: String {
        var lines = ["PlochaPro AR – měření \(Date().formatted(date: .numeric, time: .shortened))"]
        for (i, s) in segments.enumerated() { lines.append("\(i + 1)) \(Self.len(s.length))") }
        if mode == .area && points.count >= 3 {
            lines.append("Plocha: \(Self.num(area, 2)) m²  ·  obvod \(Self.len(perimeter))\(closed ? "" : " (neuzavřeno)")")
            for i in 0..<(closed ? points.count : points.count - 1) {
                lines.append("  hrana \(i + 1): \(Self.len(simd_distance(points[i], points[(i + 1) % points.count])))")
            }
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
