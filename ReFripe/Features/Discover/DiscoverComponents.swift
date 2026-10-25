import SwiftUI

// Small building blocks shared by Discover and Product.

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

// MARK: - Scarcity tag (one signal max per card)

struct ListingScarcityTag: View {
    let listing: Listing

    static func shows(_ listing: Listing) -> Bool { listing.isLastPiece || listing.views > 150 }

    var body: some View {
        if listing.isLastPiece {
            label("Dernière pièce")
        } else if listing.views > 150 {
            label("\(Fmt.number(listing.views)) vues aujourd'hui")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(RF.T.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Capsule().fill(RF.C.ink0.opacity(0.6)))
    }
}

// MARK: - Drop countdown (one discreet line)

/// "Nouveaux arrivages dans HH:MM:SS", ticking every second against `repo.nextDropDate()`.
struct DropCountdownLine: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .font(RF.T.footnote)
        .foregroundStyle(RF.C.textDim)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let remaining = date.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
        HStack(spacing: 4) {
            Image(systemName: "clock").imageScale(.small).accessibilityHidden(true)
            if let remaining, remaining > 0 {
                Text("Nouveaux arrivages dans")
                Text(Self.format(remaining)).monospacedDigit()
            } else if remaining != nil {
                Text("Nouveaux arrivages en ligne")
            } else {
                Text("Nouveaux arrivages bientôt")
            }
        }
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#Preview {
    VStack(spacing: 16) {
        DropCountdownLine(date: .now.addingTimeInterval(2 * 3600 + 14 * 60))
        DiscoverWrapLayout {
            ForEach(Catalog.brands, id: \.self) { b in
                Chip(b, selected: b == "Nike") {}
            }
        }
    }
    .padding()
    .previewEnvironment()
}
