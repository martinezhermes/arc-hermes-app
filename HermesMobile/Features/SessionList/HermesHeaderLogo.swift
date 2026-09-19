import SwiftUI

/// Pixel lettering shared by the sidebar and appearance previews. The paths are
/// built once; tint changes repaint the mark without loading or resizing artwork.
struct HermesHeaderLogo: View {
    let selectedColor: Color

    private static let lettering = PixelLettering()

    var body: some View {
        Canvas { context, size in
            let letters = Self.lettering
            context.scaleBy(x: size.width / letters.width, y: size.height / 12)
            context.translateBy(x: 0.6, y: 0.6)

            var depth = context
            depth.translateBy(x: 0.8, y: 1.5)
            depth.fill(letters.face, with: .color(selectedColor.opacity(0.25)))
            depth.stroke(letters.edge, with: .color(selectedColor.opacity(0.5)), lineWidth: 0.3)

            var inset = context
            inset.translateBy(x: 0.4, y: 0.8)
            inset.fill(letters.face, with: .color(.black))
            inset.stroke(letters.edge, with: .color(selectedColor.opacity(0.7)), lineWidth: 0.2)

            context.stroke(letters.edge, with: .color(.black), lineWidth: 0.6)
            context.fill(letters.face, with: .color(selectedColor), style: FillStyle(antialiased: false))
            context.fill(letters.face, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.44),
                    .init(color: .black.opacity(0.18), location: 0.45),
                    .init(color: .black.opacity(0.38), location: 1)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: 9)
            ))
            context.stroke(letters.highlight, with: .color(.white.opacity(0.45)), lineWidth: 0.14)
        }
        .aspectRatio(4.8, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ARC HERMES")
    }
}

private struct PixelLettering {
    let face: Path
    let edge: Path
    let highlight: Path
    let width: CGFloat

    init() {
        // Seven-column glyphs use two-cell stems and square, stepped corners.
        let glyphs: [Character: [UInt8]] = [
            "A": [0b0011100, 0b0111110, 0b1100011, 0b1100011, 0b1111111, 0b1111111, 0b1100011, 0b1100011, 0b1100011],
            "R": [0b1111110, 0b1111111, 0b1100011, 0b1100011, 0b1111110, 0b1111100, 0b1101100, 0b1100110, 0b1100011],
            "C": [0b0011111, 0b0111111, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b0111111, 0b0011111],
            "H": [0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b1111111, 0b1100011, 0b1100011, 0b1100011],
            "E": [0b1111111, 0b1111111, 0b1100000, 0b1100000, 0b1111110, 0b1111110, 0b1100000, 0b1111111, 0b1111111],
            "M": [0b1100011, 0b1110111, 0b1111111, 0b1101011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011],
            "S": [0b0111111, 0b1111111, 0b1100000, 0b1111100, 0b0111110, 0b0000011, 0b0000011, 0b1111111, 0b1111110]
        ]
        var face = Path()
        var edge = Path()
        var highlight = Path()
        var origin: CGFloat = 0

        for character in "ARC HERMES" {
            guard let rows = glyphs[character] else {
                origin += 3
                continue
            }
            func filled(_ x: Int, _ y: Int) -> Bool {
                (0..<7).contains(x) && rows.indices.contains(y) && rows[y] & (1 << (6 - x)) != 0
            }
            for y in rows.indices {
                for x in 0..<7 where filled(x, y) {
                    let cell = CGRect(x: origin + CGFloat(x), y: CGFloat(y), width: 1, height: 1)
                    face.addRect(cell)
                    let sides: [(Bool, CGPoint, CGPoint, Bool)] = [
                        (!filled(x, y - 1), CGPoint(x: cell.minX, y: cell.minY), CGPoint(x: cell.maxX, y: cell.minY), true),
                        (!filled(x - 1, y), CGPoint(x: cell.minX, y: cell.minY), CGPoint(x: cell.minX, y: cell.maxY), true),
                        (!filled(x + 1, y), CGPoint(x: cell.maxX, y: cell.minY), CGPoint(x: cell.maxX, y: cell.maxY), false),
                        (!filled(x, y + 1), CGPoint(x: cell.minX, y: cell.maxY), CGPoint(x: cell.maxX, y: cell.maxY), false)
                    ]
                    for (exposed, start, end, catchesLight) in sides where exposed {
                        edge.move(to: start)
                        edge.addLine(to: end)
                        if catchesLight {
                            highlight.move(to: start)
                            highlight.addLine(to: end)
                        }
                    }
                }
            }
            origin += 8
        }
        self.face = face
        self.edge = edge
        self.highlight = highlight
        width = origin + 1
    }
}
