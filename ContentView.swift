import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = MeasureModel()
    @State private var share: ShareItem?

    var body: some View {
        ZStack {
            ARMeasureView(model: model).ignoresSafeArea()

            // zaměřovač
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(model.aimValid ? Color.white : Color.white.opacity(0.35))
                .shadow(radius: 2)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                Picker("Režim", selection: $model.mode) {
                    ForEach(MeasureModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                info
                Spacer()
                if let d = model.liveDistance {
                    Text(MeasureModel.len(d))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(Color.white)
                }
                buttons
            }
            .padding()
        }
        .sheet(item: $share) { ActivityView(items: $0.items) }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.status.isEmpty { Text(model.status).font(.footnote).foregroundStyle(.yellow) }
            if model.mode == .circle {
                if let c = model.circle {
                    Text("\(MeasureModel.num(c.area, 2)) m²").font(.title2.bold()).foregroundStyle(.orange)
                    Text("r = \(MeasureModel.len(c.radius))  ·  Ø \(MeasureModel.len(2 * c.radius))  ·  obvod \(MeasureModel.len(c.circumference))").font(.footnote)
                    Text("Bodů: \(model.points.count)  ·  odchylka ±\(MeasureModel.len(c.rms))\(model.points.count < 6 ? "  ·  víc bodů = přesnější" : "")").font(.caption)
                } else {
                    Text("Míři na okraj kruhu a mačkej ＋ na různých místech obvodu. Stačí 3 body, víc bodů = přesnější.").font(.footnote)
                }
            } else if model.mode == .area {
                if model.points.count >= 3 {
                    Text("\(MeasureModel.num(model.area, 2)) m²").font(.title2.bold()).foregroundStyle(.orange)
                    Text("Obvod \(MeasureModel.len(model.perimeter))  ·  bodů: \(model.points.count)\(model.closed ? "" : " · neuzavřeno")").font(.footnote)
                } else {
                    Text("Míři křížkem na rohy a mačkej ＋. Uzavřeš tlačítkem nebo míření na první bod.").font(.footnote)
                }
            } else if model.segments.isEmpty {
                Text("Míři křížkem na první bod, zmáčkni ＋, pak na druhý bod a znovu ＋.").font(.footnote)
            } else {
                ForEach(Array(model.segments.enumerated()), id: \.offset) { i, s in
                    Text("\(i + 1): \(MeasureModel.len(s.length))").font(.headline)
                }
            }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            circleButton("arrow.uturn.backward") { model.undo() }
            circleButton("trash") { model.clear() }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.addPoint()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(.orange, lineWidth: 5))
                    .foregroundStyle(.black)
            }
            .disabled(!model.aimValid)
            .opacity(model.aimValid ? 1 : 0.5)
            if model.mode == .area && !model.closed && model.points.count >= 3 {
                circleButton("checkmark") { model.closeArea() }
            } else {
                circleButton("square.and.arrow.up") {
                    var items: [Any] = [model.summary]
                    if let img = model.snapshot?() { items.insert(img, at: 0) }
                    share = ShareItem(items: items)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3.bold())
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.white.opacity(0.9)))
                .foregroundStyle(.black)
        }
    }
}

struct ShareItem: Identifiable { let id = UUID(); let items: [Any] }

/// Systémové sdílení (Zprávy, WhatsApp, Uložit obrázek, Poznámky…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
