import SwiftUI

// Small building blocks shared by Discover, Product and Offers (agent A).

// MARK: - Wrapping layout (tags, filter pills)

/// Lays subviews out left-to-right, wrapping to a new line when the proposed width is exceeded.
struct DiscoverWrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += width
            widest = max(widest, x)
            x += spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if x > bounds.minX, x + width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Scarcity tag (mockup `scarcityTag` / `.scarcity`)

struct ListingScarcityTag: View {
    let listing: Listing

    static func shows(_ listing: Listing) -> Bool { listing.isLastPiece || listing.views > 150 }

    var body: some View {
        if listing.isLastPiece {
            label(symbol: "flame.fill", text: "Dernière pièce")
        } else if listing.views > 150 {
            label(symbol: "eye.fill", text: "\(Fmt.number(listing.views)) vues aujourd'hui")
        }
    }

    private func label(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(RF.F.body(9.5, .bold))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(Capsule().fill(RF.C.ink0.opacity(0.72)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Drop countdown (mockup `.dropbanner`)

/// "Nouveaux arrivages dans HH:MM:SS", ticking every second against `repo.nextDropDate()`.
struct DropCountdownBanner: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [RF.C.hibiscus.opacity(0.12), RF.C.marigold.opacity(0.14)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        )
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let remaining = date.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RF.C.hibiscus)
                .accessibilityHidden(true)
            Group {
                if let remaining, remaining > 0 {
                    Text("Nouveaux arrivages dans ")
                        + Text(Self.format(remaining)).font(RF.F.mono(11.5, .semibold)).foregroundStyle(RF.C.hibiscus)
                } else if remaining != nil {
                    Text("Nouveaux arrivages en ligne, fonce !")
                } else {
                    Text("Nouveaux arrivages bientôt")
                }
            }
            .font(RF.F.body(11, .semibold))
            .foregroundStyle(RF.C.text)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Selectable pill (mockup `.brand-chip`, marigold when active)

struct DiscoverPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RF.F.body(12, .bold))
                .foregroundStyle(selected ? RF.C.ink0 : RF.C.text)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? RF.C.marigold : RF.C.card))
                .overlay(Capsule().strokeBorder(selected ? RF.C.marigold : RF.C.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle(scale: 0.95))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 16) {
        DropCountdownBanner(date: .now.addingTimeInterval(2 * 3600 + 14 * 60))
        DiscoverWrapLayout {
            ForEach(Catalog.brands, id: \.self) { b in
                DiscoverPill(title: b, selected: b == "Nike") {}
            }
        }
    }
    .padding()
    .previewEnvironment()
}
