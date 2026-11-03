import SwiftUI

/// After COMPLETED: the buyer rates the seller (1–5 stars + one optional sentence) → `submitReview`.
struct ReviewSheet: View {
    let order: Order
    let sellerName: String
    var onDone: () -> Void = {}

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var comment = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: RF.S.xl) {
                Text(sellerName)
                    .font(RF.T.headline)
                    .foregroundStyle(RF.C.text)

                HStack(spacing: RF.S.xs) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            rating = value
                        } label: {
                            Image(systemName: value <= rating ? "star.fill" : "star")
                                .font(RF.T.title)
                                .foregroundStyle(value <= rating ? RF.C.marigold : RF.C.textDim)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RFPressStyle(scale: 0.9))
                        .accessibilityLabel("\(value) étoile\(value > 1 ? "s" : "")")
                        .accessibilityAddTraits(value == rating ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: rating)

                TextField("Un mot (facultatif)", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .padding(RF.S.md)
                    .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1))

                RFButton("Envoyer", isLoading: isSending) { Task { await send() } }
                    .disabled(rating == 0)
            }
            .padding(RF.S.gutter)
            .frame(maxHeight: .infinity, alignment: .top)
            .rfScreenBackground()
            .navigationTitle("Noter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        guard rating > 0, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await store.repo.submitReview(orderId: order.id, rating: rating,
                                                  comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            store.show("Merci")
            onDone()
            dismiss()
        } catch {
            Haptics.error()
            store.show(error)
        }
    }
}
