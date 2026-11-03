import SwiftUI

// MARK: - Reusable row

/// Conversation row (Messages tab): avatar, username + verified, relative date, preview, unread count, listing thumbnail.
struct ConversationListRow: View {
    let conversation: Conversation
    let profile: UserProfile?
    let listing: Listing?
    let action: () -> Void

    private var unread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Avatar(profile: profile, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile?.username ?? "…")
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        if profile?.verified == true { VerifiedBadge(size: 12) }
                        Spacer(minLength: 8)
                        Text(Fmt.relative(conversation.lastMessageAt))
                            .font(RF.T.footnote.monospacedDigit())
                            .foregroundStyle(unread ? RF.C.hibiscusText : RF.C.textDim)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(conversation.lastMessage.isEmpty ? "Nouvelle conversation" : conversation.lastMessage)
                            .font(unread ? RF.T.subheadline.weight(.semibold) : RF.T.subheadline)
                            .foregroundStyle(unread ? RF.C.text : RF.C.textDim)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if unread {
                            Text("\(conversation.unreadCount)")
                                .font(RF.T.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(RF.C.card)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule().fill(RF.C.hibiscus))
                        }
                    }
                    if let listing {
                        Text(listing.title)
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let listing {
                    ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, RF.S.gutter)
            .contentShape(Rectangle())
        }
        .buttonStyle(ConversationRowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var accessibilityText: String {
        var parts = [profile?.username ?? "Conversation"]
        if let listing { parts.append("à propos de \(listing.title)") }
        if unread { parts.append("\(conversation.unreadCount) non lu\(conversation.unreadCount > 1 ? "s" : "")") }
        parts.append(conversation.lastMessage)
        parts.append(Fmt.relative(conversation.lastMessageAt))
        return parts.joined(separator: ", ")
    }
}

/// Native-looking row highlight.
private struct ConversationRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RF.C.paperDim : Color.clear)
    }
}
