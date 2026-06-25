import SwiftUI
import CoreGraphics

// MARK: - Spectrogram image

/// Build a warm spectrogram image from a `[col][row]` grid (row 0 = low freq).
/// Energy ramps from the cream ground up through purple to amber, with a gamma
/// lift so quiet detail still reads (the lanes were too faint before).
func makeSpectrogramImage(_ grid: [[Float]]) -> Image? {
    guard !grid.isEmpty, let rows = grid.first?.count, rows > 0 else { return nil }
    let cols = grid.count
    var px = [UInt8](repeating: 0, count: cols * rows * 4)
    // cream → purple → amber ramp
    let stops: [(Double, (Double, Double, Double))] = [
        (0.0, (236, 230, 218)), (0.45, (107, 87, 143)), (1.0, (221, 162, 74)),
    ]
    func ramp(_ t: Double) -> (Double, Double, Double) {
        for i in 1..<stops.count where t <= stops[i].0 {
            let (a, ca) = stops[i - 1], (b, cb) = stops[i]
            let f = (t - a) / max(1e-6, b - a)
            return (ca.0 + (cb.0 - ca.0) * f, ca.1 + (cb.1 - ca.1) * f, ca.2 + (cb.2 - ca.2) * f)
        }
        return stops.last!.1
    }
    for c in 0..<cols {
        for r in 0..<rows {
            let v = pow(Double(grid[c][r]), 0.6) // gamma lift
            let y = rows - 1 - r                 // low freq at bottom
            let o = (y * cols + c) * 4
            let (cr, cg, cb) = ramp(v)
            px[o + 0] = UInt8(max(0, min(255, cr)))
            px[o + 1] = UInt8(max(0, min(255, cg)))
            px[o + 2] = UInt8(max(0, min(255, cb)))
            px[o + 3] = UInt8(min(255, v * 255))
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &px, width: cols, height: rows, bitsPerComponent: 8,
        bytesPerRow: cols * 4, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cg = ctx.makeImage() else { return nil }
    return Image(decorative: cg, scale: 1, orientation: .up).resizable().interpolation(.medium)
}

// MARK: - Per-stem spectrogram lane

/// A spectrogram strip with a played-region tint, measure grid markers, a moving
/// play cursor, and tap/drag-to-seek (the web gold master's per-stem lane).
struct SpectrogramLane: View {
    let image: Image?
    var progress: Double
    var grid: [Double]            // normalized measure-boundary positions
    var height: CGFloat = 34
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Stem.creamDeep.opacity(0.4))
                image?.resizable().frame(width: w, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                // measure grid markers
                ForEach(Array(grid.enumerated()), id: \.offset) { _, g in
                    Rectangle().fill(Stem.ink.opacity(0.06)).frame(width: 1)
                        .offset(x: w * CGFloat(g))
                }
                // played region tint
                Rectangle().fill(Stem.amber.opacity(0.10))
                    .frame(width: max(0, w * CGFloat(progress)))
                // play cursor
                Rectangle().fill(Stem.amber).frame(width: 2)
                    .shadow(color: Stem.amber.opacity(0.6), radius: 3)
                    .offset(x: w * CGFloat(progress) - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onEnded { v in onSeek(min(1, max(0, v.location.x / w))) })
        }
        .frame(height: height)
    }
}

// MARK: - Radial spectrum + warm matte disc (on-brand: no black, no neon)

/// Audio-reactive radial spectrum: amber recessed-LED ticks around the disc,
/// like light behind frosted material (PRODUCT.md). Mirrored for symmetry.
struct RadialSpectrumView: View {
    var spectrum: [Float]
    var playing: Bool

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = min(size.width, size.height) * 0.42
            let maxBar = min(size.width, size.height) * 0.07
            let n = 96
            for i in 0..<n {
                // mirror the (rows-length) spectrum across the circle
                let half = n / 2
                let idx = i < half ? i : (n - 1 - i)
                let s = spectrum.isEmpty ? 0 : Double(spectrum[min(idx * spectrum.count / half, spectrum.count - 1)])
                let mag = pow(s, 0.7)
                let len = 1.5 + mag * maxBar
                let angle = (Double(i) / Double(n)) * 2 * .pi - .pi / 2
                let a = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
                let b = CGPoint(x: center.x + cos(angle) * (inner + len), y: center.y + sin(angle) * (inner + len))
                var path = Path(); path.move(to: a); path.addLine(to: b)
                ctx.stroke(path, with: .color(Stem.amber.opacity(0.25 + mag * 0.6)), lineWidth: 2)
            }
        }
        .opacity(playing ? 1 : 0.55)
        .animation(.easeOut(duration: 0.09), value: spectrum)
    }
}

/// Warm matte disc that rotates while playing, with the play/pause control at
/// center. Cream and tonal, not a black vinyl record (brand anti-reference).
struct SpinningDiscView: View {
    var playing: Bool
    var action: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { timeline in
            let angle = playing
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12 * 360
                : 0
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [Stem.cream, Stem.creamDeep],
                    center: .center, startRadius: 6, endRadius: 150))
                    .overlay(Circle().stroke(Stem.creamDeep, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
                // faint tonal grooves (warm, not white-on-black)
                ForEach(0..<5) { i in
                    Circle().stroke(Stem.ink.opacity(0.04), lineWidth: 1).padding(CGFloat(20 + i * 13))
                }
                // a single warm index mark so rotation is legible
                Capsule().fill(Stem.amber.opacity(0.55))
                    .frame(width: 3, height: 16)
                    .offset(y: -min(120, 120))
                    .padding(.top, 6)
                Circle().fill(Stem.purple.opacity(0.10)).padding(64)
            }
            .rotationEffect(.degrees(angle))
            .overlay(
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Stem.purple)
            )
            .contentShape(Circle())
            .onTapGesture { action() }
        }
    }
}
