import SwiftUI

/// Round avatar (mockup `.avatar`): SF initial on marigold, or the profile photo when available.
struct Avatar: View {
    let initial: String
    var url: URL?
    var size: CGFloat

    init(profile: UserProfile?, size: CGFloat = 38) {
        self.initial = profile?.initial ?? "?"
        self.url = profile?.avatarURL
        self.size = size
    }

    init(name: String, size: CGFloat = 38) {
        self.initial = String(name.prefix(1)).uppercased()
        self.url = nil
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(RF.C.marigold)
            Text(initial)
                .font(RFSymbol.font(for: size * 0.4).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(RF.C.ink0)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Maps a legacy point size (icons, initials) to the closest `RF.T` text style, so it follows Dynamic Type.
enum RFSymbol {
    static func font(for points: CGFloat) -> Font {
        switch points {
        case ..<12.5: RF.T.caption
        case ..<14: RF.T.footnote
        case ..<15.5: RF.T.subheadline
        case ..<16.5: RF.T.callout
        case ..<18: RF.T.body
        case ..<21: RF.T.title3
        case ..<26: RF.T.title
        default: RF.T.largeTitle
        }
    }
}

/// Green "verified" seal shown next to a username (mockup `.verified`).
struct VerifiedBadge: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(RFSymbol.font(for: size))
            .foregroundStyle(RF.C.money)
            .accessibilityLabel("Profil vérifié")
    }
}

/// v3 seal next to a pseudo: `checkmark.seal.fill` in money green, read « Vérifiée » by VoiceOver.
/// Same look as `VerifiedBadge`, with the v3 wording; prefer it in new code.
struct VerifiedSeal: View {
    var size: CGFloat

    init(size: CGFloat = 14) { self.size = size }

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(RFSymbol.font(for: size))
            .foregroundStyle(RF.C.money)
            .accessibilityLabel("Vérifiée")
    }
}

/// Five stars (filled / half / empty) for a 0…5 rating, marigold. Decorative: callers give the spoken label.
struct RatingStars: View {
    let rating: Double
    var size: CGFloat

    init(rating: Double, size: CGFloat = 12) {
        self.rating = rating
        self.size = size
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: symbol(for: i))
                    .font(RFSymbol.font(for: size))
                    .foregroundStyle(RF.C.marigold)
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct Avatar_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            Avatar(name: "Awa_Style225")
            Avatar(name: "Karim", size: 56)
            HStack(spacing: 5) {
                Text("Awa_Style225").font(RF.T.subheadline.weight(.semibold))
                VerifiedSeal()
            }
            RatingStars(rating: 4.5)
        }
        .padding()
        .rfScreenBackground()
    }
}
