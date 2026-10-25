import SwiftUI
import PhotosUI
import UIKit

/// One photo of the draft: shown as soon as it is picked, then checked on-device.
struct SellPhoto: Identifiable {
    let id = UUID()
    var analysis: SellPhotoAnalysis?
    var isChecking: Bool { analysis == nil }
}

/// State of the 10-step sell wizard (mockup `screenSell`, `SELL_STEPS`, `freshSellDraft`).
@MainActor
@Observable
final class SellFlowModel {
    enum Step: Int, CaseIterable, Identifiable {
        case photos = 1, category, brand, size, condition, color, details, price, delivery, review
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .photos: "Photos"
            case .category: "Catégorie"
            case .brand: "Marque"
            case .size: "Taille"
            case .condition: "État"
            case .color: "Couleur"
            case .details: "Description"
            case .price: "Prix"
            case .delivery: "Livraison"
            case .review: "Publier"
            }
        }
        var previous: Step? { Step(rawValue: rawValue - 1) }
        var next: Step? { Step(rawValue: rawValue + 1) }
    }

    static let titleMax = 60
    static let descriptionMax = 1_000
    static let defectMax = 300
    static let priceRange: ClosedRange<FCFA> = 250...1_000_000
    static let handDeliveryHint: FCFA = 2_000

    var step: Step = .photos
    /// Direction of the last move, for the slide transition.
    var movingForward = true
    /// Set when a step is edited from the review screen: "Continuer" jumps back to the review.
    var returnToReview = false

    var draft = ListingDraft()
    var photos: [SellPhoto] = []
    var isPublishing = false
    var published: Listing?

    /// Routed to `store.show` by the view.
    @ObservationIgnored var notify: (String) -> Void = { _ in }

    // MARK: Navigation

    func go(to target: Step) {
        movingForward = target.rawValue >= step.rawValue
        withAnimation(.snappy(duration: 0.3)) { step = target }
    }

    func back() {
        guard let previous = step.previous else { return }
        go(to: previous)
    }

    func advance() {
        guard canContinue(step) else { return }
        if returnToReview {
            go(to: firstIncompleteStep ?? .review)
            if step == .review { returnToReview = false }
        } else if let next = step.next {
            go(to: next)
        }
    }

    func edit(_ target: Step) {
        returnToReview = true
        go(to: target)
    }

    var isDirty: Bool {
        !photos.isEmpty || draft.gender != nil || draft.brand != nil || draft.condition != nil || draft.color != nil
            || !draft.title.isEmpty || !draft.description.isEmpty || !draft.defectComment.isEmpty
    }

    func reset() {
        draft = ListingDraft()
        photos = []
        published = nil
        returnToReview = false
        movingForward = false
        step = .photos
    }

    // MARK: Validation (mockup `canContinue`)

    func canContinue(_ s: Step) -> Bool {
        switch s {
        case .photos:
            photos.count >= Catalog.sellPhotoMin && photos.allSatisfy { !$0.isChecking } && flaggedPhotos.isEmpty
        case .category: draft.gender != nil
        case .brand:
            draft.brand != nil && (draft.brand != SellFlowModel.otherBrand || !trimmed(draft.brandCustom).isEmpty)
        case .size: draft.sizeType != nil && draft.sizeValue != nil
        case .condition: draft.condition != nil
        case .color: draft.color != nil
        case .details: !trimmed(draft.title).isEmpty && draft.title.count <= Self.titleMax
        case .price:
            Self.priceRange.contains(draft.price) && (!draft.negotiable || (draft.minOffer > 0 && draft.minOffer < draft.price))
        case .delivery: !draft.delivery.isEmpty
        case .review: firstIncompleteStep == nil && !isPublishing
        }
    }

    var firstIncompleteStep: Step? {
        Step.allCases.first { $0 != .review && !canContinue($0) }
    }

    /// Why the bottom button is disabled (shown under it), if it is.
    var blockingHint: String? {
        guard !canContinue(step) else { return nil }
        switch step {
        case .photos:
            if photos.contains(where: \.isChecking) { return "Contrôle qualité en cours…" }
            if !flaggedPhotos.isEmpty { return "Retire les photos signalées." }
            return Catalog.sellPhotoMin > 1 ? "Ajoute au moins \(Catalog.sellPhotoMin) photos." : "Ajoute au moins une photo."
        case .category: return "Choisis une catégorie."
        case .brand: return draft.brand == SellFlowModel.otherBrand ? "Précise la marque." : "Choisis une marque."
        case .size: return "Choisis une taille."
        case .condition: return "Indique l'état de l'article."
        case .color: return "Choisis la couleur dominante."
        case .details:
            return draft.title.count > Self.titleMax ? "Le titre est trop long." : "Donne un titre à ton annonce."
        case .price:
            if !Self.priceRange.contains(draft.price) {
                return "Le prix doit être compris entre \(Fmt.fcfa(Self.priceRange.lowerBound)) et \(Fmt.fcfa(Self.priceRange.upperBound))."
            }
            return "L'offre minimum doit être inférieure au prix."
        case .delivery: return "Choisis au moins un mode de remise."
        case .review:
            if isPublishing { return nil }
            return firstIncompleteStep.map { "À compléter : \($0.title.lowercased())." }
        }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Photos

    var remainingPhotoSlots: Int { max(0, Catalog.sellPhotoMax - photos.count) }

    /// Effective flag of a photo: its own problem, or `.duplicate` if it matches an earlier photo.
    func flag(for photo: SellPhoto) -> PhotoFlag? {
        guard let analysis = photo.analysis else { return nil }
        if let own = analysis.flag { return own }
        for other in photos {
            if other.id == photo.id { break }
            guard let o = other.analysis else { continue }
            if SellPhotoQuality.hammingDistance(o.hash, analysis.hash) <= SellPhotoQuality.duplicateMaxDistance {
                return .duplicate
            }
        }
        return nil
    }

    var flaggedPhotos: [(index: Int, flag: PhotoFlag)] {
        var result: [(index: Int, flag: PhotoFlag)] = []
        for (i, p) in photos.enumerated() {
            if let f = flag(for: p) { result.append((index: i, flag: f)) }
        }
        return result
    }

    func importItems(_ items: [PhotosPickerItem]) {
        let accepted = Array(items.prefix(remainingPhotoSlots))
        if accepted.count < items.count { notify("Maximum \(Catalog.sellPhotoMax) photos par annonce.") }
        for item in accepted {
            let photo = SellPhoto()
            photos.append(photo)
            let id = photo.id
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw RepositoryError.invalidState("format inconnu")
                    }
                    await check(id: id, data: data, source: .library)
                } catch {
                    discard(id, message: "Impossible de charger une photo.")
                }
            }
        }
    }

    func addCameraImage(_ image: UIImage) {
        guard remainingPhotoSlots > 0, let data = image.jpegData(compressionQuality: 0.9) else { return }
        let photo = SellPhoto()
        photos.append(photo)
        let id = photo.id
        Task { await check(id: id, data: data, source: .camera) }
    }

    private func check(id: UUID, data: Data, source: SellPhotoSource) async {
        let analysis = await SellPhotoQuality.analyze(data, source: source)
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        guard let analysis else {
            discard(id, message: "Cette image n'a pas pu être lue.")
            return
        }
        photos[index].analysis = analysis
        if flag(for: photos[index]) != nil { Haptics.warning() }
    }

    private func discard(_ id: UUID, message: String) {
        photos.removeAll { $0.id == id }
        notify(message)
    }

    func removePhoto(_ id: UUID) {
        withAnimation(.snappy) { photos.removeAll { $0.id == id } }
    }

    func makeCover(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }), index > 0 else { return }
        withAnimation(.snappy) {
            let photo = photos.remove(at: index)
            photos.insert(photo, at: 0)
        }
    }

    // MARK: Brand / size / title helpers

    static let otherBrand = "Autre"

    /// Size systems that make sense for the chosen category.
    var allowedSizeTypes: [SizeType] {
        switch draft.gender {
        case .femme?, .homme?: [.haut, .pantalon, .chaussures, .unique]
        case .enfant?, .bebe?: [.enfant, .chaussures, .unique]
        case nil: SizeType.allCases
        }
    }

    func setGender(_ gender: Gender) {
        draft.gender = gender
        if let type = draft.sizeType, !allowedSizeTypes.contains(type) {
            draft.sizeType = nil
            draft.sizeValue = nil
        }
    }

    func setSizeType(_ type: SizeType) {
        guard draft.sizeType != type else { return }
        draft.sizeType = type
        draft.sizeValue = type == .unique ? type.options.first : nil
    }

    /// « {marque} {catégorie} {couleur} », e.g. "Zara Femme noir".
    var suggestedTitle: String? {
        let brand = trimmed(draft.resolvedBrand)
        let parts = [brand == "Sans marque précise" ? "" : brand,
                     draft.gender?.label ?? "",
                     draft.color?.lowercased() ?? ""].filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let title = String(parts.joined(separator: " ").prefix(Self.titleMax))
        return title == trimmed(draft.title) ? nil : title
    }

    var brandLabel: String {
        let b = trimmed(draft.resolvedBrand)
        return b.isEmpty ? "Non précisée" : b
    }

    var sizeLabel: String {
        guard let type = draft.sizeType, let value = draft.sizeValue else { return "—" }
        return type.displayLabel(for: value)
    }

    // MARK: Price helpers

    var priceStep: FCFA { OfferRules.step(for: draft.price) }

    /// Keeps the private floor strictly below the price (mockup `data-sell-price-step`).
    func clampMinOffer() {
        let step = priceStep
        if draft.minOffer >= draft.price { draft.minOffer = max(step, draft.price - step) }
    }

    // MARK: Publish

    func publish(using store: AppStore) async {
        guard canContinue(.review) else { return }
        isPublishing = true
        defer { isPublishing = false }
        var output = draft
        output.photos = photos.compactMap { $0.analysis?.jpeg }
        output.title = trimmed(draft.title)
        output.description = trimmed(draft.description)
        output.defectComment = trimmed(draft.defectComment)
        output.brandCustom = trimmed(draft.brandCustom)
        do {
            let listing = try await store.repo.publish(output)
            Haptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { published = listing }
        } catch {
            Haptics.error()
            store.show(error)
        }
    }

    var coverImage: UIImage? { photos.first?.analysis?.thumbnail }
}
