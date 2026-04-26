import SwiftUI

struct ProgressRing: View {
    let value: Int
    let goal: Int
    var size: CGFloat = 280
    var stroke: CGFloat = 18
    var color: Color
    var track: Color

    @State private var animatedPct: Double = 0

    /// The raw ratio of steps to goal, clamped to 1.0. We also snap values
    /// in the last 1.5% up to a full ring — between ~0.985 and 1.0 the
    /// arc's start and end round caps collide into an ugly blob at 12
    /// o'clock, so we skip that narrow zone entirely and jump straight to
    /// the clean closed-shape render.
    private var pct: Double {
        let raw = min(1, Double(value) / Double(max(goal, 1)))
        return raw > 0.985 ? 1.0 : raw
    }

    var body: some View {
        ZStack {
            // Track — the resting channel behind the progress arc.
            Circle()
                .stroke(track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Bloom — a blurred, lower-opacity twin of the arc. Butt cap
            // (instead of round) avoids the overhang past the trim start
            // that was creating a darker halo reaching into the empty
            // half of the ring. The blur softens the flat ends naturally.
            Circle()
                .trim(from: 0, to: animatedPct)
                .stroke(color.opacity(0.4),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .blur(radius: 10)

            // Arc — vertical LinearGradient: top of the ring sits at a
            // gentle 0.7-opacity sage, bottom at full strength. Linear
            // gradients don't wrap the way angular ones do, so the round
            // cap at 12 o'clock matches the adjacent arc color cleanly —
            // no darker tail.
            Circle()
                .trim(from: 0, to: animatedPct)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.7), color],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) { animatedPct = pct }
        }
        .onChange(of: pct) { _, new in
            withAnimation(.easeOut(duration: 1.2)) { animatedPct = new }
        }
    }
}
