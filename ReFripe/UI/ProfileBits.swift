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
                .font(.system(size: size * 0.4, weight: .semibold))
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

/// Green "verified" seal shown next to a username (mockup `.verified`).
struct VerifiedBadge: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .foregroundStyle(RF.C.money)
            .accessibilityLabel("Profil vérifié")
    }
}

struct Avatar_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            Avatar(name: "Awa_Style225")
            Avatar(name: "Karim", size: 56)
            HStack(spacing: 5) {
                Text("Awa_Style225").font(RF.T.subheadline.weight(.semibold))
                VerifiedBadge()
            }
        }
        .padding()
        .rfScreenBackground()
    }
}
