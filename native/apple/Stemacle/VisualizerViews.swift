import SwiftUI
import CoreGraphics

// MARK: - Spectrogram image

/// Build a warm spectrogram image from a `[col][row]` grid (row 0 = low freq).
/// Energy ramps purple→amber on a transparent ground so it reads on cream.
func makeSpectrogramImage(_ grid: [[Float]]) -> Image? {
    guard !grid.isEmpty, let rows = grid.first?.count, rows > 0 else { return nil }
    let cols = grid.count
    var px = [UInt8](repeating: 0, count: cols * rows * 4)
    let purple: (Double, Double, Double) = (107, 87, 143)
    let amber: (Double, Double, Double) = (217, 158, 71)
    for c in 0..<cols {
        for r in 0..<rows {
            let v = Double(grid[c][r])
            // image y is top-down; put low freq (row 0) at the bottom
            let y = rows - 1 - r
            let o = (y * cols + c) * 4
            let t = min(1, max(0, v))
            px[o + 0] = UInt8(purple.0 + (amber.0 - purple.0) * t)
            px[o + 1] = UInt8(purple.1 + (amber.1 - purple.1) * t)
            px[o + 2] = UInt8(purple.2 + (amber.2 - purple.2) * t)
            px[o + 3] = UInt8(pow(t, 0.8) * 235)
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

/// A spectrogram strip with a play cursor and tap/drag-to-seek (matches the web
/// gold master's per-stem lane).
struct SpectrogramLane: View {
    let image: Image?
    var progress: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Stem.creamDeep.opacity(0.35))
                image?
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                // play cursor
                Rectangle()
                    .fill(Stem.amber)
                    .frame(width: 1.5)
                    .offset(x: geo.size.width * progress)
                    .opacity(0.9)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { v in onSeek(min(1, max(0, v.location.x / geo.size.width))) }
            )
        }
        .frame(height: 34)
    }
}

// MARK: - Radial EDM spectrum + spinning disc

/// Audio-reactive radial spectrum ring (the 2016-EDM look): bars radiate from a
/// circle, heights driven by the current spectrum.
struct RadialSpectrumView: View {
    var spectrum: [Float]
    var playing: Bool

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = min(size.width, size.height) * 0.30
            let maxBar = min(size.width, size.height) * 0.18
            let n = max(48, spectrum.count)
            for i in 0..<n {
                let s = spectrum.isEmpty ? 0 : Double(spectrum[i % spectrum.count])
                let mag = pow(s, 0.7)
                let len = 3 + mag * maxBar
                // mirror the spectrum around the circle for symmetry
                let angle = (Double(i) / Double(n)) * 2 * .pi - .pi / 2
                let a = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
                let b = CGPoint(x: center.x + cos(angle) * (inner + len),
                                y: center.y + sin(angle) * (inner + len))
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                let warm = Color(red: 0.42 + mag * 0.4, green: 0.34 + mag * 0.25, blue: 0.56)
                ctx.stroke(path, with: .color(warm.opacity(0.55 + mag * 0.45)), lineWidth: 2.2)
            }
        }
        .opacity(playing ? 1 : 0.5)
        .animation(.easeOut(duration: 0.08), value: spectrum)
    }
}

/// A vinyl-style disc that spins while playing, with the play/pause control at
/// its center.
struct SpinningDiscView: View {
    var playing: Bool
    var action: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { timeline in
            let angle = playing
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
                : 0
            ZStack {
                // vinyl
                Circle().fill(
                    RadialGradient(colors: [Color(white: 0.14), Color(white: 0.05)],
                                   center: .center, startRadius: 4, endRadius: 130)
                )
                // grooves
                ForEach(0..<7) { i in
                    Circle().stroke(Color.white.opacity(0.05), lineWidth: 1)
                        .padding(CGFloat(10 + i * 9))
                }
                // center label
                Circle().fill(Stem.purple).padding(58)
                Circle().fill(Color(white: 0.05)).frame(width: 8, height: 8) // spindle
            }
            .rotationEffect(.degrees(angle))
            .overlay(
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            )
            .contentShape(Circle())
            .onTapGesture { action() }
        }
    }
}
