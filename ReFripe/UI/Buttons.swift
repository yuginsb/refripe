import SwiftUI

/// Full-width button from the mockup (`.btn`): radius 12, padding 13, Manrope ExtraBold 13.5.
/// `.primary` = hibiscus, `.secondary` = paper-dim, `.ink` = dark, `.ghost` = outlined.
struct RFButton: View {
    enum Style { case primary, secondary, ink, ghost }

    let title: String
    var symbol: String?
    var style: Style
    var isLoading: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, symbol: String? = nil, style: Style = .primary, isLoading: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    private var fgColor: Color {
        switch style {
        case .primary: .white
        case .secondary, .ghost: RF.C.text
        case .ink: RF.C.paper
        }
    }

    private var bgColor: Color {
        switch style {
        case .primary: RF.C.hibiscus
        case .secondary: RF.C.paperDim
        case .ink: RF.C.ink1
        case .ghost: .clear
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView().tint(fgColor)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(RF.F.body(13.5, .extraBold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(fgColor)
            .frame(maxWidth: .infinity, minHeight: 20)
            .padding(13)
            .background(bgColor, in: shape)
            .overlay {
                if style == .ghost { shape.strokeBorder(RF.C.line, lineWidth: 1.5) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(RFPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

/// Press feedback used across the kit (mockup `.card:active { transform: scale(0.97) }`).
struct RFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RFButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            RFButton("Acheter maintenant", symbol: "lock.fill") {}
            RFButton("Faire une offre", symbol: "arrow.left.arrow.right", style: .ghost) {}
            RFButton("Voir le tableau de bord", style: .ink) {}
            RFButton("Plus tard", style: .secondary) {}
            RFButton("Paiement…", isLoading: true) {}
            RFButton("Désactivé") {}.disabled(true)
        }
        .padding()
        .rfScreenBackground()
    }
}
