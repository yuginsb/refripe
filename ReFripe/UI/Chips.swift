import SwiftUI

/// Filter chip (mockup `.chip`): selected = ink, otherwise paper-dim; optional hibiscus count badge.
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
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(RF.F.body(11.5, .bold)).lineLimit(1)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(RF.F.body(9, .extraBold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Circle().fill(RF.C.hibiscus))
                }
            }
            .foregroundStyle(selected ? RF.C.paper : RF.C.text)
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .background(Capsule().fill(selected ? RF.C.ink1 : RF.C.paperDim))
            .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle(scale: 0.95))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(badge.map { $0 > 0 ? "\(title), \($0) actifs" : title } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Order status pill (mockup `.order-status-pill.pill-*`), coloured by `OrderStatus.tone`.
struct StatusPill: View {
    let status: OrderStatus

    private var colors: (bg: Color, fg: Color) {
        switch status.tone {
        case .progress: (RF.C.marigold.opacity(0.2), Color(hex: 0x93601A))
        case .done: (RF.C.money.opacity(0.18), RF.C.moneyDeep)
        case .cancelled: (RF.C.hibiscus.opacity(0.18), Color(hex: 0xA8382C))
        case .alert: (RF.C.hibiscus.opacity(0.14), Color(hex: 0xA8601F))
        }
    }

    var body: some View {
        Text(status.label)
            .font(RF.F.body(9.5, .extraBold))
            .foregroundStyle(colors.fg)
            .multilineTextAlignment(.trailing)
            .lineSpacing(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.bg))
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
