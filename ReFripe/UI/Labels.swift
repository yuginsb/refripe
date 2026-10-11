import SwiftUI

/// Small uppercase section title (mockup `.co-label`).
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(RF.F.mono(11, .semibold))
            .kerning(0.66)
            .foregroundStyle(RF.C.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Dashboard tile (mockup `.dash-stat`): optional icon, mono value, label, green delta.
struct StatTile: View {
    let title: String
    let value: String
    var delta: String?
    var symbol: String?

    init(title: String, value: String, delta: String? = nil, symbol: String? = nil) {
        self.title = title
        self.value = value
        self.delta = delta
        self.symbol = symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(RF.C.text)
                    .padding(.bottom, 6)
            }
            Text(value)
                .font(RF.F.mono(17, .semibold))
                .monospacedDigit()
                .foregroundStyle(RF.C.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(RF.F.body(10.5))
                .foregroundStyle(RF.C.textDim)
                .padding(.top, 2)
            if let delta {
                Text(delta)
                    .font(RF.F.body(9.5, .bold))
                    .foregroundStyle(RF.C.moneyDeep)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct Labels_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SectionLabel("Mode de paiement")
            HStack(spacing: 10) {
                StatTile(title: "Ventes ce mois", value: "4", delta: "+1 vs mois dernier", symbol: "bag")
                StatTile(title: "Revenus", value: Fmt.fcfa(75_000), delta: "+17 000 FCFA vs mois dernier", symbol: "banknote")
            }
        }
        .padding()
        .rfScreenBackground()
    }
}
