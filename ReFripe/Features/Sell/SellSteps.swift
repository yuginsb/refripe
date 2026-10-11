import SwiftUI
import PhotosUI
import UIKit

// The ten steps of the sell wizard (mockup `sellStepPhotos` … `sellStepReview`).

// MARK: - 1. Photos

struct SellPhotosStep: View {
    @Bindable var model: SellFlowModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @FocusState private var defectFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Entre \(Catalog.sellPhotoMin) et \(Catalog.sellPhotoMax) photos. Chaque photo passe un contrôle automatique : flou, contenu sensible, doublon, screenshot, watermark professionnel.")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    slot(photo, index: index)
                }
                if model.remainingPhotoSlots > 0 {
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: model.remainingPhotoSlots,
                                 selectionBehavior: .ordered,
                                 matching: .images,
                                 preferredItemEncoding: .current) {
                        addSlot(symbol: "plus", label: "Ajouter")
                    }
                    .accessibilityLabel("Ajouter des photos depuis la photothèque")
                    if SellCameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            addSlot(symbol: "camera", label: "Photographier")
                        }
                        .accessibilityLabel("Prendre une photo")
                    }
                }
            }
            .padding(.bottom, 14)

            if !model.flaggedPhotos.isEmpty { warning }

            Text("\(model.photos.count)/\(Catalog.sellPhotoMax) photos · la première sert de couverture")
                .font(RF.F.mono(10.5))
                .foregroundStyle(RF.C.textDim)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 0) {
                SellFieldLabel(text: "Photographie aussi les défauts (tache, trou, accroc…)", symbol: "camera",
                               counter: model.draft.defectComment.isEmpty ? nil
                                   : "\(model.draft.defectComment.count)/\(SellFlowModel.defectMax)")
                TextField("Commentaire sur un défaut (optionnel)", text: $model.draft.defectComment, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($defectFocused)
                    .sellField(focused: defectFocused)
                    .onChange(of: model.draft.defectComment) { _, new in
                        if new.count > SellFlowModel.defectMax { model.draft.defectComment = String(new.prefix(SellFlowModel.defectMax)) }
                    }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            model.importItems(items)
            pickerItems = []
        }
        .fullScreenCover(isPresented: $showCamera) {
            SellCameraPicker { image in model.addCameraImage(image) }
                .ignoresSafeArea()
        }
    }

    private func slot(_ photo: SellPhoto, index: Int) -> some View {
        let flag = model.flag(for: photo)
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        return RF.C.paperDim
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = photo.analysis?.thumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().tint(RF.C.textDim)
                }
            }
            .overlay(alignment: .bottom) {
                if let flag {
                    Text(flag.label)
                        .font(RF.F.body(8.5, .extraBold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity)
                        .background(RF.C.hibiscus.opacity(0.92))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(flag == nil ? Color.clear : RF.C.hibiscus, lineWidth: 2))
            .overlay(alignment: .topLeading) {
                if index == 0 && !photo.isChecking && flag == nil {
                    Text("Couverture")
                        .font(RF.F.body(8, .extraBold))
                        .foregroundStyle(RF.C.ink0)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(RF.C.marigold))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if flag == nil { statusBadge(photo).padding(4) }
            }
            .overlay(alignment: .topTrailing) {
                Button { model.removePhoto(photo.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(RF.C.ink0.opacity(0.65)))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle(scale: 0.85))
                .accessibilityLabel("Retirer la photo \(index + 1)")
            }
            .contextMenu {
                if index > 0 {
                    Button { model.makeCover(photo.id) } label: { Label("Utiliser en couverture", systemImage: "star") }
                }
                Button(role: .destructive) { model.removePhoto(photo.id) } label: { Label("Retirer", systemImage: "trash") }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel(photo, index: index, flag: flag))
    }

    @ViewBuilder private func statusBadge(_ photo: SellPhoto) -> some View {
        if photo.isChecking {
            EmptyView()
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(RF.C.money))
        }
    }

    private func accessibilityLabel(_ photo: SellPhoto, index: Int, flag: PhotoFlag?) -> String {
        let base = "Photo \(index + 1)"
        if photo.isChecking { return "\(base), contrôle en cours" }
        if let flag { return "\(base), refusée : \(flag.label)" }
        return index == 0 ? "\(base), couverture, validée" : "\(base), validée"
    }

    private func addSlot(symbol: String, label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        return VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(label).font(RF.F.body(9.5, .bold))
        }
        .foregroundStyle(RF.C.textDim)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(RF.C.paperDim, in: shape)
        .overlay(shape.strokeBorder(RF.C.text.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(shape)
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.flaggedPhotos, id: \.index) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                    Text("Photo \(item.index + 1) : \(item.flag.label) — remplace ou retire cette photo.")
                }
            }
        }
        .font(RF.F.body(11, .semibold))
        .foregroundStyle(RF.C.hibiscus)
        .lineSpacing(2)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RF.C.hibiscus.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2. Catégorie

struct SellCategoryStep: View {
    @Bindable var model: SellFlowModel
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            SellTagline("Dans quelle catégorie se range cet article ?")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Gender.allCases) { gender in
                    tile(gender)
                }
            }
        }
    }

    private func tile(_ gender: Gender) -> some View {
        let selected = model.draft.gender == gender
        let shape = RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous)
        return Button { model.setGender(gender) } label: {
            VStack(spacing: 8) {
                Image(systemName: gender.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
                    .frame(height: 32)
                Text(gender.label).font(RF.F.body(12, .bold)).foregroundStyle(RF.C.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 10)
            .background(selected ? RF.C.hibiscus.opacity(0.08) : RF.C.card, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.hibiscus : RF.C.line, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(gender.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 3. Marque

struct SellBrandStep: View {
    @Bindable var model: SellFlowModel
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Sélectionne la marque, ou « Autre » si elle n'est pas listée.")
            SellFlowLayout {
                ForEach(Catalog.brands + [SellFlowModel.otherBrand], id: \.self) { brand in
                    SellPill(title: brand, selected: model.draft.brand == brand) {
                        model.draft.brand = brand
                        if brand == SellFlowModel.otherBrand { customFocused = true }
                    }
                }
            }
            if model.draft.brand == SellFlowModel.otherBrand {
                VStack(alignment: .leading, spacing: 0) {
                    SellFieldLabel(text: "Précise la marque")
                    TextField("Ex : Woodin, Vlisco…", text: $model.draft.brandCustom)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($customFocused)
                        .sellField(focused: customFocused)
                        .onSubmit { model.advance() }
                }
                .padding(.top, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: model.draft.brand)
    }
}

// MARK: - 4. Taille

struct SellSizeStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Quel type de taille pour cet article ?")
            SellFlowLayout {
                ForEach(model.allowedSizeTypes) { type in
                    SellPill(title: typeLabel(type), selected: model.draft.sizeType == type, accent: .ink) {
                        model.setSizeType(type)
                    }
                }
            }
            .padding(.bottom, 18)

            if let type = model.draft.sizeType {
                if type == .unique {
                    SellTagline("Parfait, aucune taille supplémentaire à préciser.")
                } else {
                    SectionLabel(type == .chaussures ? "Pointure" : "Taille")
                        .padding(.bottom, 10)
                    SellFlowLayout {
                        ForEach(type.options, id: \.self) { value in
                            SellPill(title: value, selected: model.draft.sizeValue == value, accent: .ink) {
                                model.draft.sizeValue = value
                            }
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: model.draft.sizeType)
    }

    private func typeLabel(_ type: SizeType) -> String {
        switch type {
        case .haut: "Vêtement · haut"
        case .pantalon: "Vêtement · bas"
        case .chaussures: "Chaussures"
        case .enfant: "Taille enfant"
        case .unique: "Taille unique"
        }
    }
}

// MARK: - 5. État

struct SellConditionStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Décris honnêtement l'état — ça évite les litiges après achat.")
            SellFlowLayout {
                ForEach(ItemCondition.allCases) { condition in
                    SellPill(title: condition.label, selected: model.draft.condition == condition) {
                        model.draft.condition = condition
                    }
                }
            }
        }
    }
}

// MARK: - 6. Couleur

struct SellColorStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Quelle est la couleur dominante ?")
            SellFlowLayout {
                ForEach(Catalog.colors, id: \.self) { color in
                    SellPill(title: color, selected: model.draft.color == color,
                             swatch: SellColorSwatch.style(for: color)) {
                        model.draft.color = color
                    }
                }
            }
        }
    }
}

// MARK: - 7. Titre + description

struct SellDetailsStep: View {
    @Bindable var model: SellFlowModel
    private enum Field { case title, description }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Matière, coupe, historique de l'article — plus c'est précis, moins tu auras de questions en message.")

            SellFieldLabel(text: "Titre", counter: "\(model.draft.title.count)/\(SellFlowModel.titleMax)")
            TextField("Ex : Robe wax cintrée", text: $model.draft.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focus, equals: .title)
                .sellField(focused: focus == .title)
                .onSubmit { focus = .description }
                .onChange(of: model.draft.title) { _, new in
                    if new.count > SellFlowModel.titleMax { model.draft.title = String(new.prefix(SellFlowModel.titleMax)) }
                }

            if let suggestion = model.suggestedTitle {
                Button {
                    model.draft.title = suggestion
                    Haptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .semibold))
                        Text("Suggestion : ").font(RF.F.body(11.5)) + Text(suggestion).font(RF.F.body(11.5, .bold))
                    }
                    .foregroundStyle(RF.C.text)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 11)
                    .background(Capsule().fill(RF.C.paperDim))
                }
                .buttonStyle(RFPressStyle(scale: 0.96))
                .padding(.top, 8)
                .accessibilityLabel("Utiliser le titre suggéré : \(suggestion)")
            }

            SellFieldLabel(text: "Description",
                           counter: "\(model.draft.description.count)/\(SellFlowModel.descriptionMax)")
                .padding(.top, 20)
            TextField("Ex : Robe en pagne wax authentique, coupe cintrée, portée 3 fois seulement…",
                      text: $model.draft.description, axis: .vertical)
                .lineLimit(6...12)
                .focused($focus, equals: .description)
                .sellField(focused: focus == .description)
                .onChange(of: model.draft.description) { _, new in
                    if new.count > SellFlowModel.descriptionMax {
                        model.draft.description = String(new.prefix(SellFlowModel.descriptionMax))
                    }
                }
            Text("Facultatif, mais une bonne description vend plus vite.")
                .font(RF.F.body(10.5))
                .foregroundStyle(RF.C.textDim)
                .padding(.top, 6)
        }
        .onAppear { if model.draft.title.isEmpty { focus = .title } }
    }
}

// MARK: - 8. Prix

struct SellPriceStep: View {
    @Bindable var model: SellFlowModel
    @State private var priceText = ""
    @FocusState private var priceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Fixe ton prix — tu pourras toujours l'ajuster plus tard.")

            PriceStepper(value: $model.draft.price, step: model.priceStep, range: SellFlowModel.priceRange)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

            HStack(spacing: 8) {
                TextField("Saisir un montant", text: $priceText)
                    .keyboardType(.numberPad)
                    .focused($priceFocused)
                    .font(RF.F.mono(14, .semibold))
                    .multilineTextAlignment(.center)
                Text("FCFA").font(RF.F.mono(12)).foregroundStyle(RF.C.textDim)
            }
            .sellField(focused: priceFocused)
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .accessibilityLabel("Prix en FCFA")

            segmented
                .padding(.top, 20)
                .padding(.bottom, 18)

            if model.draft.negotiable {
                VStack(alignment: .leading, spacing: 0) {
                    SellFieldLabel(text: "Offre minimum acceptée", symbol: "lock")
                    PriceStepper(value: $model.draft.minOffer, step: model.priceStep, range: minOfferRange, compact: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    Text("Privée : jamais montrée aux acheteuses. Elle t’aide à juger chaque offre : tu restes libre d’accepter, de refuser ou de contre-proposer.")
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                        .padding(.top, 6)
                }
                .padding(14)
                .rfCard()
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))

                SellTagline("Les acheteuses pourront proposer un prix ; tu gardes la main pour accepter, refuser ou contre-proposer, avec un plafond de \(OfferRules.maxBuyerOffers) échanges.")
            }
        }
        .animation(.snappy, value: model.draft.negotiable)
        .onAppear { priceText = String(model.draft.price) }
        .onChange(of: model.draft.price) { _, new in
            if !priceFocused { priceText = String(new) }
            model.clampMinOffer()
        }
        .onChange(of: priceText) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(7))
            if digits != new { priceText = digits; return }
            if priceFocused, let value = Int(digits) { model.draft.price = value }
        }
        .onChange(of: priceFocused) { _, focused in
            guard !focused else { return }
            let r = SellFlowModel.priceRange
            model.draft.price = min(r.upperBound, max(r.lowerBound, model.draft.price))
            priceText = String(model.draft.price)
        }
    }

    private var minOfferRange: ClosedRange<FCFA> {
        let step = model.priceStep
        return step...max(step, model.draft.price - step)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            segment("Prix fixe", symbol: "lock", active: !model.draft.negotiable) { model.draft.negotiable = false }
            segment("Ouvert aux offres", symbol: "arrow.left.arrow.right", active: model.draft.negotiable) {
                model.draft.negotiable = true
                model.clampMinOffer()
            }
        }
        .padding(3)
        .background(Capsule().fill(RF.C.paperDim))
        .sensoryFeedback(.selection, trigger: model.draft.negotiable)
    }

    private func segment(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(RF.F.body(12, .bold))
            }
            .foregroundStyle(active ? RF.C.text : RF.C.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if active {
                    Capsule().fill(RF.C.card).shadow(color: RF.C.text.opacity(0.1), radius: 3, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 9. Livraison

struct SellDeliveryStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SellTagline("Comment les acheteuses peuvent-elles récupérer l'article ? Tu peux en cocher plusieurs.")
                .padding(.bottom, -10)
            ForEach(DeliveryMethod.allCases) { method in
                SellMethodRow(symbol: method.symbol, title: method.label, subtitle: method.subtitle,
                              trailing: method.fee == 0 ? "Gratuit" : "~\(Fmt.fcfa(method.fee))",
                              selected: model.draft.delivery.contains(method)) {
                    if model.draft.delivery.contains(method) { model.draft.delivery.remove(method) }
                    else { model.draft.delivery.insert(method) }
                }
            }
            tip.padding(.top, 6)
        }
    }

    private var tip: some View {
        let cheap = model.draft.price < SellFlowModel.handDeliveryHint
        let missingHand = !model.draft.delivery.contains(.mainPropre)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 15))
                .foregroundStyle(RF.C.marigold)
            VStack(alignment: .leading, spacing: 4) {
                Text("La remise en main propre est idéale sous \(Fmt.fcfa(SellFlowModel.handDeliveryHint)) : pas de frais pour l'acheteuse, la vente se conclut plus vite.")
                    .font(RF.F.body(11.5))
                    .foregroundStyle(RF.C.text)
                    .lineSpacing(2)
                if cheap && missingHand {
                    Button("Ajouter la main propre") {
                        model.draft.delivery.insert(.mainPropre)
                    }
                    .font(RF.F.body(11.5, .extraBold))
                    .foregroundStyle(RF.C.hibiscus)
                }
                Text("Les frais de livraison sont à la charge de l'acheteuse.")
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RF.C.marigold.opacity(0.14), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }
}

// MARK: - 10. Relecture

struct SellReviewStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Dernière vérification avant publication. Touche une ligne pour la modifier.")

            VStack(alignment: .leading, spacing: 0) {
                photos.padding(.bottom, 12)

                HStack(spacing: 8) {
                    Text(Fmt.fcfa(model.draft.price))
                        .font(RF.F.mono(19, .semibold))
                        .foregroundStyle(RF.C.text)
                    negotiationTag
                    Spacer(minLength: 0)
                    editIcon
                }
                .contentShape(Rectangle())
                .onTapGesture { model.edit(.price) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Modifier le prix")

                if !model.draft.title.isEmpty {
                    Text(model.draft.title)
                        .font(RF.F.display(14, .semibold))
                        .foregroundStyle(RF.C.text)
                        .padding(.top, 8)
                        .onTapGesture { model.edit(.details) }
                }

                VStack(spacing: 0) {
                    row("Photos", "\(model.photos.count)", .photos)
                    row("Catégorie", model.draft.gender?.label ?? "—", .category)
                    row("Marque", model.brandLabel, .brand)
                    row("Taille", model.sizeLabel, .size)
                    row("État", model.draft.condition?.label ?? "—", .condition)
                    row("Couleur", model.draft.color ?? "—", .color)
                    if model.draft.negotiable {
                        row("Offre minimum", Fmt.fcfa(model.draft.minOffer) + " (privée)", .price)
                    }
                    row("Livraison", deliveryLabel, .delivery, last: true)
                }
                .padding(.top, 12)

                if !model.draft.description.isEmpty {
                    Text(model.draft.description)
                        .font(RF.F.body(12.5))
                        .foregroundStyle(RF.C.text)
                        .lineSpacing(3)
                        .padding(.top, 12)
                        .onTapGesture { model.edit(.details) }
                }
                if !model.draft.defectComment.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                        Text("Défauts : \(model.draft.defectComment)")
                    }
                    .font(RF.F.body(11.5))
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, 10)
                    .onTapGesture { model.edit(.photos) }
                }
            }
            .padding(14)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        }
    }

    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    RF.C.paper
                        .frame(width: index == 0 ? 160 : 100, height: 160)
                        .overlay {
                            if let image = photo.analysis?.thumbnail {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(height: 160)
        .onTapGesture { model.edit(.photos) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.photos.count) photos")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Modifier les photos")
    }

    @ViewBuilder private var negotiationTag: some View {
        let negotiable = model.draft.negotiable
        HStack(spacing: 5) {
            Image(systemName: negotiable ? "arrow.left.arrow.right" : "lock").font(.system(size: 10, weight: .semibold))
            Text(negotiable ? "Offres acceptées" : "Prix fixe")
        }
        .font(RF.F.body(11, .semibold))
        .foregroundStyle(negotiable ? RF.C.moneyDeep : RF.C.textDim)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(negotiable ? RF.C.money.opacity(0.14) : RF.C.text.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var editIcon: some View {
        Image(systemName: "pencil")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(RF.C.textDim)
    }

    private var deliveryLabel: String {
        let labels = DeliveryMethod.allCases.filter { model.draft.delivery.contains($0) }.map { method -> String in
            switch method {
            case .relais: "Point relais"
            case .mainPropre: "Main propre"
            case .yango: "Yango"
            }
        }
        return labels.isEmpty ? "Non précisé" : labels.joined(separator: " · ")
    }

    private func row(_ label: String, _ value: String, _ step: SellFlowModel.Step, last: Bool = false) -> some View {
        Button { model.edit(step) } label: {
            HStack(spacing: 8) {
                Text(label).foregroundStyle(RF.C.textDim)
                Spacer(minLength: 12)
                Text(value)
                    .font(RF.F.body(12, .bold))
                    .foregroundStyle(RF.C.text)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RF.C.textDim.opacity(0.7))
            }
            .font(RF.F.body(12))
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(RF.C.line).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) : \(value)")
        .accessibilityHint("Modifier")
    }
}
