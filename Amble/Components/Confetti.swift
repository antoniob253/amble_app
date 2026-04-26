import SwiftUI

struct Confetti: View {
    let palette: Palette
    @State private var pieces: [Piece] = []

    struct Piece: Identifiable {
        let id = UUID()
        let x: Double
        let color: Color
        let delay: Double
        let rotation: Double
        let duration: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    ConfettiPiece(piece: p, geoSize: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { spawn() }
    }

    private func spawn() {
        let colors = [palette.accent, palette.accent2, palette.positive]
        pieces = (0..<28).map { i in
            Piece(
                x: 0.1 + Double.random(in: 0...0.8),
                color: colors[i % colors.count],
                delay: Double.random(in: 0...0.3),
                rotation: Double.random(in: 0...360),
                duration: 1.6 + Double.random(in: 0...0.8)
            )
        }
    }
}

private struct ConfettiPiece: View {
    let piece: Confetti.Piece
    let geoSize: CGSize
    @State private var fallen = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(piece.color)
            .frame(width: 8, height: 14)
            .rotationEffect(.degrees(piece.rotation + (fallen ? 720 : 0)))
            .position(
                x: piece.x * geoSize.width,
                y: fallen ? geoSize.height + 40 : -20
            )
            .opacity(fallen ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: piece.duration).delay(piece.delay)) {
                    fallen = true
                }
            }
    }
}
