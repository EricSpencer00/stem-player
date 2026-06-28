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

// MARK: - Per-stem spectrogram / waveform lane (scrolling window)

/// A lane that shows a sliding 30-second time window: the play cursor stays at
/// 25% from the left so the lane scrolls like the web gold master.
///
/// `image` is the full-track spectrogram (macOS). `envelope` is the peak
/// waveform (iOS, avoids STFT OOM). Pass whichever is non-empty.
struct SpectrogramLane: View {
    let image: Image?
    let envelope: [Float]          // iOS waveform fallback; empty on macOS
    var progress: Double           // global 0..1 play position
    var duration: Double           // total track seconds
    var grid: [Double]             // measure boundaries 0..1 (global)
    var height: CGFloat = 34
    var onSeek: (Double) -> Void

    private let windowSec: Double = 30    // visible window width in seconds
    private let headFrac: Double  = 0.25  // playhead at 25% of window

    private var windowStart: Double {
        guard duration > 0 else { return 0 }
        let preferred = progress * duration - headFrac * windowSec
        let maxStart  = max(0, duration - windowSec)
        return max(0, min(preferred, maxStart))
    }

    var body: some View {
        GeometryReader { geo in
            let W      = geo.size.width
            let H      = geo.size.height
            let wStart = windowStart
            let wEnd   = wStart + windowSec
            let cursorX = duration > 0
                ? ((progress * duration - wStart) / windowSec).clamped(to: 0...1)
                : headFrac

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Stem.creamDeep.opacity(0.4))

                if let img = image {
                    // Full-track spectrogram: the image is W*(duration/windowSec)
                    // pixels wide; shift it left so windowStart aligns with x=0.
                    let scale    = duration > 0 ? duration / windowSec : 1
                    let totalW   = W * CGFloat(scale)
                    let offsetX  = -W * CGFloat(wStart / windowSec)
                    img.resizable()
                        .frame(width: totalW, height: H)
                        .offset(x: offsetX)
                        .clipped()

                } else if !envelope.isEmpty {
                    // iOS waveform fallback: render bars for the visible window.
                    Canvas { ctx, size in
                        let cols   = envelope.count
                        let c0     = Int((wStart / max(duration, 1)) * Double(cols))
                        let c1     = min(cols, Int((wEnd / max(duration, 1)) * Double(cols)) + 1)
                        let vis    = max(1, c1 - c0)
                        let barW   = size.width / CGFloat(vis)
                        for i in 0..<vis {
                            let ci = (c0 + i).clamped(to: 0...(cols - 1))
                            let v  = CGFloat(envelope[ci])
                            let bH = size.height * v
                            let y  = (size.height - bH) / 2
                            let r  = CGRect(x: CGFloat(i) * barW, y: y,
                                            width: max(1, barW - 0.5), height: bH)
                            ctx.fill(Path(r),
                                     with: .color(Stem.purple.opacity(0.4 + 0.35 * v)))
                        }
                    }
                }

                // Measure grid: only markers visible in the current window
                ForEach(Array(grid.enumerated()), id: \.offset) { _, g in
                    let gSec = g * duration
                    if gSec >= wStart && gSec <= wEnd {
                        let xFrac = (gSec - wStart) / windowSec
                        Rectangle().fill(Stem.ink.opacity(0.06)).frame(width: 1)
                            .offset(x: W * CGFloat(xFrac))
                    }
                }

                // Played-region tint
                Rectangle().fill(Stem.amber.opacity(0.10))
                    .frame(width: max(0, W * CGFloat(cursorX)))

                // Play cursor — stays near headFrac, clamped at track edges
                Rectangle().fill(Stem.amber).frame(width: 2)
                    .shadow(color: Stem.amber.opacity(0.6), radius: 3)
                    .offset(x: W * CGFloat(cursorX) - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onEnded { v in
                    let frac    = max(0, min(1, v.location.x / W))
                    let seekSec = wStart + frac * windowSec
                    onSeek(max(0, min(1, duration > 0 ? seekSec / duration : 0)))
                })
        }
        .frame(height: height)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
