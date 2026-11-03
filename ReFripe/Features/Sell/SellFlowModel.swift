import SwiftUI
import PhotosUI
import UIKit

/// One photo of the draft: shown as soon as it is picked, then checked on-device.
struct SellPhoto: Identifiable {
    let id = UUID()
    var analysis: SellPhotoAnalysis?
    var isChecking: Bool { analysis == nil }
}

/// State of the 4-step sell wizard (v3): Photos · L'article · Ton prix · Remise (+ relecture) → Publier.
/// The draft is saved to disk on every step change and restored the next time « Vendre » opens.
@MainActor
@Observable
final class SellFlowModel {
    enum Step: Int, CaseIterable, Identifiable {
        case photos = 1, article, price, review
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .photos: "Photos"
            case .article: "L'article"
            case .price: "Ton prix"
            case .review: "Remise"
            }
        }
        var previous: Step? { Step(rawValue: rawValue - 1) }
        var next: Step? { Step(rawValue: rawValue + 1) }
    }

    static let titleMax = 60
    static let descriptionMax = 1_000
    static let defectMax = 300
    static let brandMax = 40
    static let priceRange: ClosedRange<FCFA> = 250...1_000_000
    static let handDeliveryHint: FCFA = 2_000
    /// Default private floor when the seller types a price (share of the price).
    static let defaultMinOfferRatio = 0.7

    var step: Step = .photos
    /// Direction of the last move, for the slide transition.
    var movingForward = true
    /// Set when a step is edited from the review screen: "Continuer" jumps back to the review.
    var returnToReview = false

    var draft = ListingDraft()
    var photos: [SellPhoto] = []
    var isPublishing = false
    var published: Listing?

    /// When the draft was last written to disk (nil = nothing saved) → « Brouillon enregistré ».
    var draftSavedAt: Date?
    /// Last title we generated, so a title the seller typed herself is never overwritten.
    var autoTitle: String?
    /// « Similaires : 2 000 – 4 500 FCFA » on the price step (nil = not loaded / not enough data).
    var similarPriceRange: ClosedRange<FCFA>?

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
        if step == .article { applyAutoTitle() }
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
        !photos.isEmpty || draft.itemType != nil || draft.gender != nil || draft.condition != nil
            || draft.price > 0 || !trimmed(draft.title).isEmpty || !trimmed(draft.description).isEmpty
            || !trimmed(draft.defectComment).isEmpty || !(draft.brand ?? "").isEmpty || draft.color != nil
    }

    /// Clears the in-memory form (not the disk: see `startOver`).
    func reset() {
        draft = ListingDraft()
        photos = []
        published = nil
        returnToReview = false
        movingForward = false
        choseOneSize = false
        autoTitle = nil
        similarPriceRange = nil
        step = .photos
    }

    /// « Recommencer »: empties the form and deletes the saved draft.
    func startOver() {
        SellDraftStore.clear()
        draftSavedAt = nil
        withAnimation(.snappy) { reset() }
    }

    // MARK: Validation

    func canContinue(_ s: Step) -> Bool {
        switch s {
        case .photos:
            photos.count >= Catalog.sellPhotoMin && photos.allSatisfy { !$0.isChecking } && flaggedPhotos.isEmpty
        case .article:
            draft.itemType != nil && draft.gender != nil && draft.sizeType != nil && draft.sizeValue != nil
                && draft.condition != nil
        case .price:
            // v3: price starts empty (0 = invalid until typed); the private floor must stay under the price.
            Self.priceRange.contains(draft.price)
                && (!draft.negotiable || (draft.minOffer > 0 && draft.minOffer < draft.price))
        case .review:
            !draft.delivery.isEmpty && !trimmed(draft.title).isEmpty && draft.title.count <= Self.titleMax
                && firstIncompleteStep == nil && !isPublishing
        }
    }

    /// First step before the review that still blocks publishing.
    var firstIncompleteStep: Step? {
        Step.allCases.first { $0 != .review && !canContinue($0) }
    }

    /// Why the bottom button is disabled (shown under it), if it is. Short on purpose.
    var blockingHint: String? {
        guard !canContinue(step) else { return nil }
        switch step {
        case .photos:
            if photos.contains(where: \.isChecking) { return "Vérification…" }
            if !flaggedPhotos.isEmpty { return "Retire les photos signalées" }
            return "Ajoute une photo"
        case .article:
            if draft.itemType == nil { return "Choisis le type" }
            if draft.gender == nil { return "Choisis pour qui" }
            if draft.sizeValue == nil { return "Choisis la taille" }
            return "Choisis l'état"
        case .price:
            if draft.price == 0 { return "Indique un prix" }
            if !Self.priceRange.contains(draft.price) {
                return "Entre \(Fmt.fcfa(Self.priceRange.lowerBound)) et \(Fmt.fcfa(Self.priceRange.upperBound))"
            }
            return "Offre min. trop haute"
        case .review:
            if isPublishing { return nil }
            if let missing = firstIncompleteStep { return "À compléter : \(missing.title.lowercased())" }
            if draft.delivery.isEmpty { return "Choisis une remise" }
            return draft.title.count > Self.titleMax ? "Titre trop long" : "Ajoute un titre"
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
        if accepted.count < items.count { notify("\(Catalog.sellPhotoMax) photos max.") }
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

    // MARK: Article helpers

    /// Size grid for the chosen item type and « Pour »: shoes → pointures, kids → ages, else XS–XL / 36–44.
    var resolvedSizeType: SizeType? {
        guard let type = draft.itemType else { return nil }
        let base = type.suggestedSizeType ?? .haut
        if base == .chaussures || base == .unique { return base }
        if draft.gender == .enfant || draft.gender == .bebe { return .enfant }
        return base
    }

    func setItemType(_ type: ItemType) {
        draft.itemType = type
        syncSizeType()
    }

    func setGender(_ gender: Gender) {
        draft.gender = gender
        syncSizeType()
    }

    /// True when the seller picked « Taille unique » on a sized grid (kept across type / gender changes).
    private(set) var choseOneSize = false

    /// Keeps `draft.sizeType` in line with type / gender; resets the value when the grid changes.
    private func syncSizeType() {
        guard let target = resolvedSizeType else { return }
        if choseOneSize && draft.sizeType == .unique && target != .chaussures { return }
        choseOneSize = false
        guard draft.sizeType != target else { return }
        draft.sizeType = target
        draft.sizeValue = target == .unique ? target.options.first : nil
    }

    func selectSize(_ value: String) {
        guard let grid = resolvedSizeType else { return }
        draft.sizeType = grid
        draft.sizeValue = value
        choseOneSize = false
    }

    /// « Taille unique » chip offered next to a sized grid (pagne-like items, accessories…).
    func selectOneSize() {
        draft.sizeType = .unique
        draft.sizeValue = SizeType.unique.options.first
        choseOneSize = true
    }

    var brandText: String {
        get { draft.brand ?? "" }
        set {
            let value = String(newValue.prefix(Self.brandMax))
            draft.brand = value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
            draft.brandCustom = ""
        }
    }

    /// « Robe wax », « Baskets Nike blanc »: type + brand + colour.
    var suggestedTitle: String? {
        guard let type = draft.itemType else { return nil }
        let brand = trimmed(draft.resolvedBrand)
        let parts = [type.label,
                     brand == "Sans marque précise" ? "" : brand,
                     draft.color?.lowercased() ?? ""].filter { !$0.isEmpty }
        return String(parts.joined(separator: " ").prefix(Self.titleMax))
    }

    /// Fills the title with the suggestion unless the seller already wrote her own.
    func applyAutoTitle() {
        guard let suggestion = suggestedTitle else { return }
        let current = trimmed(draft.title)
        if current.isEmpty || current == autoTitle {
            draft.title = suggestion
            autoTitle = suggestion
        }
    }

    var brandLabel: String {
        let b = trimmed(draft.resolvedBrand)
        return b.isEmpty ? "—" : b
    }

    var sizeLabel: String {
        guard let type = draft.sizeType, let value = draft.sizeValue else { return "—" }
        return type.displayLabel(for: value)
    }

    var articleLabel: String {
        [draft.itemType?.label, draft.gender?.label].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Price helpers

    var priceStep: FCFA { OfferRules.step(for: max(draft.price, 1)) }

    /// Sets the price typed by the seller and keeps the private floor valid (defaults to ~70 % of the price).
    func setPrice(_ value: FCFA) {
        draft.price = value
        guard value > 0 else { return }
        if draft.minOffer <= 0 || draft.minOffer >= value { resetMinOffer() }
    }

    func resetMinOffer() {
        let step = priceStep
        guard draft.price > step else { draft.minOffer = 0; return }
        let floor = OfferRules.round(Double(draft.price) * Self.defaultMinOfferRatio, step: step)
        draft.minOffer = min(draft.price - step, max(step, floor))
    }

    /// Kept for source compatibility: same as before, keeps the floor strictly under the price.
    func clampMinOffer() {
        if draft.price > 0 && (draft.minOffer <= 0 || draft.minOffer >= draft.price) { resetMinOffer() }
    }

    var minOfferRange: ClosedRange<FCFA> {
        let step = priceStep
        return step...max(step, draft.price - step)
    }

    /// Price range of similar listings (same type, same « Pour »), rounded to 500.
    func loadSimilarPrices(repo: any Repository) async {
        guard let type = draft.itemType else { similarPriceRange = nil; return }
        var filters = ListingFilters()
        filters.itemTypes = [type]
        filters.gender = draft.gender
        var prices = ((try? await repo.feed(filters: filters, preferences: nil)) ?? []).map(\.price)
        if prices.count < 2 {
            filters.gender = nil
            prices = ((try? await repo.feed(filters: filters, preferences: nil)) ?? []).map(\.price)
        }
        prices.sort()
        guard prices.count >= 2 else { similarPriceRange = nil; return }
        let low: FCFA, high: FCFA
        if prices.count >= 4 {
            low = prices[prices.count / 4]
            high = prices[(prices.count * 3) / 4]
        } else {
            low = prices[0]
            high = prices[prices.count - 1]
        }
        let lo = max(250, OfferRules.round(Double(low), step: 500))
        let hi = max(lo, OfferRules.round(Double(high), step: 500))
        similarPriceRange = lo...hi
    }

    // MARK: Draft persistence

    /// Writes the draft (photos that passed the check included) — called on every step change and on close.
    func saveDraft() {
        guard published == nil else { return }
        guard isDirty else {
            SellDraftStore.clear()
            draftSavedAt = nil
            return
        }
        let snapshot = SellDraftSnapshot(
            step: step.rawValue, itemType: draft.itemType, gender: draft.gender, sizeType: draft.sizeType,
            sizeValue: draft.sizeValue, condition: draft.condition, brand: draft.brand, color: draft.color,
            title: draft.title, description: draft.description, defectComment: draft.defectComment,
            price: draft.price, negotiable: draft.negotiable, minOffer: draft.minOffer,
            delivery: DeliveryMethod.allCases.filter { draft.delivery.contains($0) },
            autoTitle: autoTitle, savedAt: .now)
        let jpegs = photos.compactMap { photo -> Data? in
            guard flag(for: photo) == nil else { return nil }
            return photo.analysis?.jpeg
        }
        SellDraftStore.save(snapshot, photos: jpegs)
        draftSavedAt = snapshot.savedAt
    }

    /// Restores the saved draft, if any (photos are re-checked in the background).
    func restoreDraft() {
        guard !isDirty, let saved = SellDraftStore.load() else { return }
        let s = saved.snapshot
        var d = ListingDraft()
        d.itemType = s.itemType
        d.gender = s.gender
        d.sizeType = s.sizeType
        d.sizeValue = s.sizeValue
        d.condition = s.condition
        d.brand = s.brand
        d.color = s.color
        d.title = s.title
        d.description = s.description
        d.defectComment = s.defectComment
        d.price = s.price
        d.negotiable = s.negotiable
        d.minOffer = s.minOffer
        d.delivery = Set(s.delivery)
        draft = d
        autoTitle = s.autoTitle
        draftSavedAt = s.savedAt
        movingForward = true
        step = Step(rawValue: s.step) ?? .photos
        for jpeg in saved.photos.prefix(Catalog.sellPhotoMax) {
            let photo = SellPhoto()
            photos.append(photo)
            let id = photo.id
            // Already accepted once: skip the screenshot check (re-encoded JPEG has no metadata).
            Task { await check(id: id, data: jpeg, source: .camera) }
        }
        choseOneSize = d.sizeType == .unique && resolvedSizeType != .unique
        // Without photos, start again from the photo step.
        if photos.isEmpty { step = .photos }
    }

    /// UI tests: a bundled demo photo, quality flags ignored, so the walk-through can reach steps 2–4.
    func addUITestPhoto(assetName: String = "listing-1") {
        guard photos.isEmpty, let image = UIImage(named: assetName), let data = image.jpegData(compressionQuality: 0.9) else { return }
        let photo = SellPhoto()
        photos.append(photo)
        let id = photo.id
        Task {
            guard var analysis = await SellPhotoQuality.analyze(data, source: .camera) else { return }
            analysis.flag = nil
            if let index = photos.firstIndex(where: { $0.id == id }) { photos[index].analysis = analysis }
        }
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
        let brand = trimmed(draft.brand ?? "")
        output.brand = brand.isEmpty ? nil : brand
        output.brandCustom = ""
        if !output.negotiable { output.minOffer = 0 }
        do {
            let listing = try await store.repo.publish(output)
            Haptics.success()
            SellDraftStore.clear()
            draftSavedAt = nil
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { published = listing }
        } catch {
            Haptics.error()
            store.show(error)
        }
    }

    var coverImage: UIImage? { photos.first?.analysis?.thumbnail }
}
