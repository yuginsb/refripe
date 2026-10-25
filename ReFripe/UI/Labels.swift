import SwiftUI

/// Section header in content: sentence case, footnote semibold, dim (same look as a native List header).
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Stat tile: optional icon, tabular-digit value, label, optional green delta.
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
        VStack(alignment: .leading, spacing: 2) {
            if let symbol {
                Image(systemName: symbol)
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
                    .padding(.bottom, 6)
            }
            Text(value)
                .font(RF.T.number(.title3, weight: .semibold))
                .foregroundStyle(RF.C.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .lineLimit(2)
            if let delta {
                Text(delta)
                    .font(RF.T.caption.monospacedDigit())
                    .foregroundStyle(RF.C.moneyDeep)
                    .padding(.top, 4)
            }
        }
        .padding(RF.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
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
