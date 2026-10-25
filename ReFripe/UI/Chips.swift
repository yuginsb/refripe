import SwiftUI

/// Filter chip: subtle capsule, SF subheadline. Selected = hibiscus tint; optional count badge.
struct Chip: View {
    let title: String
    var selected: Bool
    var badge: Int?
    var symbol: String?
    let action: () -> Void

    init(_ title: String, selected: Bool = false, badge: Int? = nil, symbol: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.badge = badge
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                }
                Text(title).font(RF.T.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(RF.T.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(RF.C.hibiscus))
                }
            }
            .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(Capsule().fill(selected ? RF.C.hibiscus.opacity(0.10) : RF.C.card))
            .overlay(Capsule().strokeBorder(selected ? RF.C.hibiscus.opacity(0.35) : RF.C.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(badge.map { $0 > 0 ? "\(title), \($0) actifs" : title } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Order status pill, coloured by `OrderStatus.tone` with low-saturation tints.
struct StatusPill: View {
    let status: OrderStatus

    private var colors: (bg: Color, fg: Color) {
        switch status.tone {
        case .progress: (RF.C.text.opacity(0.06), RF.C.textDim)
        case .done: (RF.C.money.opacity(0.10), RF.C.moneyDeep)
        case .cancelled: (RF.C.text.opacity(0.06), RF.C.textDim)
        case .alert: (RF.C.hibiscus.opacity(0.10), Color(hex: 0xA8382C))
        }
    }

    var body: some View {
        Text(status.label)
            .font(RF.T.caption.weight(.medium))
            .foregroundStyle(colors.fg)
            .multilineTextAlignment(.trailing)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Capsule().fill(colors.bg))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Statut : \(status.label)")
    }
}

struct Chipspills_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Chip("Tout", selected: true) {}
                Chip("Femme") {}
                Chip("Filtres", badge: 2, symbol: "slider.horizontal.3") {}
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(OrderStatus.allCases, id: \.self) { StatusPill(status: $0) }
            }
        }
        .padding()
        .rfScreenBackground()
    }
}
