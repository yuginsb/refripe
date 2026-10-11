import SwiftUI
import UIKit

// Small building blocks of the sell wizard, styled after the mockup's `.auth-*`, `.field`, `.brand-chip`,
// `.size-chip`, `.category-card`, `.method-btn` classes.

/// Centered helper paragraph (mockup `.auth-tagline`).
struct SellTagline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RF.F.body(12))
            .foregroundStyle(RF.C.textDim)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
    }
}

/// Uppercase field label (mockup `.field label`), optional leading symbol and trailing counter.
struct SellFieldLabel: View {
    let text: String
    var symbol: String?
    var counter: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text.uppercased())
                .font(RF.F.body(10.5, .bold))
                .kerning(0.42)
            Spacer(minLength: 8)
            if let counter {
                Text(counter).font(RF.F.mono(10)).monospacedDigit()
            }
        }
        .foregroundStyle(RF.C.textDim)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Text input chrome (mockup `.field input` / `.field textarea`).
    func sellField(focused: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return self
            .font(RF.F.body(13))
            .foregroundStyle(RF.C.text)
            .tint(RF.C.hibiscus)
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .background(RF.C.card, in: shape)
            .overlay(shape.strokeBorder(focused ? RF.C.hibiscus.opacity(0.6) : RF.C.line, lineWidth: 1.5))
    }
}

/// Selectable pill. `.marigold` = mockup `.brand-chip.active`, `.ink` = `.size-chip.active`.
struct SellPill: View {
    enum Accent { case marigold, ink }

    let title: String
    let selected: Bool
    var accent: Accent = .marigold
    var swatch: AnyShapeStyle?
    let action: () -> Void

    var body: some View {
        let fill: Color = selected ? (accent == .marigold ? RF.C.marigold : RF.C.ink1) : RF.C.card
        let fg: Color = selected ? (accent == .marigold ? RF.C.ink0 : RF.C.paper) : RF.C.text
        Button(action: action) {
            HStack(spacing: 7) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(RF.C.text.opacity(0.18), lineWidth: 1))
                }
                Text(title).font(RF.F.body(12, .bold)).lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.vertical, accent == .marigold ? 9 : 8)
            .padding(.horizontal, 14)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(selected ? fill : RF.C.line, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle(scale: 0.95))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row of pills (mockup `.brand-chips` / `.size-chips`: flex-wrap, gap 8).
struct SellFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Swatch shown next to each colour name (data colours, not theme tokens).
enum SellColorSwatch {
    static func style(for name: String) -> AnyShapeStyle {
        switch name {
        case "Noir": AnyShapeStyle(Color(hex: 0x1C1A1E))
        case "Blanc": AnyShapeStyle(Color.white)
        case "Rouge": AnyShapeStyle(Color(hex: 0xD3392C))
        case "Bleu": AnyShapeStyle(Color(hex: 0x2F5DA8))
        case "Vert": AnyShapeStyle(Color(hex: 0x2E8B57))
        case "Jaune": AnyShapeStyle(Color(hex: 0xF2C230))
        case "Orange": AnyShapeStyle(Color(hex: 0xF08A24))
        case "Marron": AnyShapeStyle(Color(hex: 0x7B4B2A))
        case "Rose": AnyShapeStyle(Color(hex: 0xF29BB8))
        default:
            AnyShapeStyle(AngularGradient(colors: [RF.C.hibiscus, RF.C.marigold, RF.C.money, Color(hex: 0x2F5DA8), RF.C.hibiscus],
                                          center: .center))
        }
    }
}

/// Large selectable row (mockup `.method-btn` / `.selected-method`).
struct SellMethodRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let trailing: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(RF.F.body(13, .bold)).foregroundStyle(RF.C.text)
                    Text(subtitle).font(RF.F.body(11)).foregroundStyle(RF.C.textDim)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? RF.C.hibiscus : RF.C.textDim.opacity(0.6))
                    Text(trailing).font(RF.F.mono(10.5, .semibold)).foregroundStyle(RF.C.textDim)
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(selected ? RF.C.hibiscus.opacity(0.06) : RF.C.card, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.hibiscus : RF.C.line, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle), \(trailing)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Camera

/// System camera (`UIImagePickerController`), only offered when a camera is available.
struct SellCameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SellCameraPicker
        init(_ parent: SellCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Confetti

/// Short confetti burst for the publish success screen (skipped with Reduce Motion).
struct SellConfettiView: View {
    fileprivate struct Piece {
        let x: CGFloat, delay: Double, speed: CGFloat, width: CGFloat, height: CGFloat
        let color: Color, spin: Double, sway: CGFloat
    }

    @State private var start = Date()
    @State private var finished = false
    @State private var pieces: [Piece] = (0..<80).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.7), speed: .random(in: 0.28...0.6),
              width: .random(in: 5...9), height: .random(in: 8...14),
              color: [RF.C.hibiscus, RF.C.marigold, RF.C.money, RF.C.ink2, RF.C.paperDim].randomElement() ?? RF.C.marigold,
              spin: .random(in: 2...7), sway: .random(in: 8...28))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = -20 + CGFloat(local) * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + CGFloat(sin(local * 3 + p.spin)) * p.sway
                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(local * p.spin))
                    let rect = CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(4.5))
            finished = true
        }
    }
}
