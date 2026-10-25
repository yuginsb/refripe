import SwiftUI
import UIKit

// Small building blocks of the sell wizard. v2: SF text styles, subtle selection (hibiscus tint), no caps.

/// One short line under the step title.
struct SellTagline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, RF.S.lg)
    }
}

/// Field label in sentence case, optional leading symbol and trailing counter.
struct SellFieldLabel: View {
    let text: String
    var symbol: String?
    var counter: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).font(RF.T.footnote.weight(.semibold))
            Spacer(minLength: 8)
            if let counter {
                Text(counter).font(RF.T.caption.monospacedDigit())
            }
        }
        .foregroundStyle(RF.C.textDim)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Simple text input chrome: white field, radius 10, hairline (hibiscus when focused).
    func sellField(focused: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return self
            .font(RF.T.body)
            .foregroundStyle(RF.C.text)
            .tint(RF.C.hibiscus)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(RF.C.card, in: shape)
            .overlay(shape.strokeBorder(focused ? RF.C.hibiscus.opacity(0.6) : RF.C.line, lineWidth: 1))
    }
}

/// Selectable pill (brand, size, colour). Both accents now share the same subtle hibiscus selection;
/// `accent` is kept for source compatibility.
struct SellPill: View {
    enum Accent { case marigold, ink }

    let title: String
    let selected: Bool
    var accent: Accent = .marigold
    var swatch: AnyShapeStyle?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(RF.C.text.opacity(0.18), lineWidth: 1))
                }
                Text(title)
                    .font(RF.T.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(Capsule().fill(selected ? RF.C.hibiscus.opacity(0.10) : RF.C.card))
            .overlay(Capsule().strokeBorder(selected ? RF.C.hibiscus.opacity(0.5) : RF.C.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle())
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

/// Selectable row with a checkmark, meant for a `Form` section (delivery methods).
struct SellMethodRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let trailing: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(RF.C.textDim)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(RF.T.body).foregroundStyle(RF.C.text)
                    Text(subtitle).font(RF.T.footnote).foregroundStyle(RF.C.textDim)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(trailing).font(RF.T.price(.subheadline, weight: .regular)).foregroundStyle(RF.C.textDim)
                Image(systemName: "checkmark")
                    .font(RF.T.body.weight(.semibold))
                    .foregroundStyle(RF.C.hibiscus)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Short confetti burst. v2: no longer shown (decoration); kept for reference/compatibility.
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
