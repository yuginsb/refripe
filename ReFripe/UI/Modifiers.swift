import SwiftUI

extension View {
    /// Full-screen paper background (also hides List/Form/ScrollView default backgrounds).
    func rfScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { RF.C.paper.ignoresSafeArea() }
    }

    /// White card, radius 14, hairline border (mockup `.card`). Content is clipped to the shape.
    func rfCard(radius: CGFloat = RF.R.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(RF.C.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(RF.C.line, lineWidth: 1))
    }
}

/// House motif: diamond lattice "taken from the pagne without copying any" (mockup `--motif`).
struct MotifPattern: View {
    var color: Color = RF.C.text.opacity(0.055)
    var spacing: CGFloat = 13
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let h = size.height
            let gap = spacing * 1.414
            var x: CGFloat = -h
            while x < size.width + h {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + h, y: h))
                path.move(to: CGPoint(x: x, y: h))
                path.addLine(to: CGPoint(x: x + h, y: 0))
                x += gap
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
