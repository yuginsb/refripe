import SwiftUI

/// Full-width button: SF headline, height 50, radius 12.
/// `.primary` = hibiscus fill (one per screen), `.secondary` = subtle tinted fill,
/// `.ink` = dark fill (kept for compatibility, use sparingly), `.ghost` = hairline outline.
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
        case .secondary: RF.C.hibiscus
        case .ghost: RF.C.text
        case .ink: RF.C.paper
        }
    }

    private var bgColor: Color {
        switch style {
        case .primary: RF.C.hibiscus
        case .secondary: RF.C.hibiscus.opacity(0.10)
        case .ink: RF.C.ink1
        case .ghost: .clear
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(fgColor)
                } else if let symbol {
                    Image(systemName: symbol).imageScale(.medium)
                }
                Text(title)
                    .font(RF.T.button)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(fgColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(bgColor, in: shape)
            .overlay {
                if style == .ghost { shape.strokeBorder(RF.C.line, lineWidth: 1) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(RFPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

/// Press feedback used across the kit: a light dim + slight scale, close to native button behaviour.
struct RFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RFButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            RFButton("Acheter", symbol: "lock.fill") {}
            RFButton("Faire une offre", style: .secondary) {}
            RFButton("Plus tard", style: .ghost) {}
            RFButton("Statistiques", style: .ink) {}
            RFButton("Paiement…", isLoading: true) {}
            RFButton("Désactivé") {}.disabled(true)
        }
        .padding()
        .rfScreenBackground()
    }
}
