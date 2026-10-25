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
            SellTagline("\(Catalog.sellPhotoMin) à \(Catalog.sellPhotoMax) photos. La première sert de couverture.")

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
                            addSlot(symbol: "camera", label: "Photo")
                        }
                        .accessibilityLabel("Prendre une photo")
                    }
                }
            }
            .padding(.bottom, RF.S.sm)

            HStack(alignment: .firstTextBaseline) {
                if model.flaggedPhotos.isEmpty {
                    Text("Contrôle auto : flou, doublon, capture, filigrane, contenu sensible.")
                        .foregroundStyle(RF.C.textDim)
                } else {
                    Label(flagSummary, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(RF.C.hibiscus)
                }
                Spacer(minLength: 8)
                Text("\(model.photos.count)/\(Catalog.sellPhotoMax)")
                    .monospacedDigit()
                    .foregroundStyle(RF.C.textDim)
            }
            .font(RF.T.footnote)
            .padding(.bottom, RF.S.xl)
            .accessibilityElement(children: .combine)

            SellFieldLabel(text: "Défauts (facultatif)",
                           counter: model.draft.defectComment.isEmpty ? nil
                               : "\(model.draft.defectComment.count)/\(SellFlowModel.defectMax)")
            TextField("Tache, trou, accroc… Photographie-les aussi.", text: $model.draft.defectComment, axis: .vertical)
                .lineLimit(2...6)
                .focused($defectFocused)
                .sellField(focused: defectFocused)
                .accessibilityLabel("Commentaire sur un défaut (optionnel)")
                .onChange(of: model.draft.defectComment) { _, new in
                    if new.count > SellFlowModel.defectMax { model.draft.defectComment = String(new.prefix(SellFlowModel.defectMax)) }
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

    /// "À retirer : photo 2 (floue), photo 3 (doublon)".
    private var flagSummary: String {
        let items = model.flaggedPhotos.map { "photo \($0.index + 1) (\($0.flag.shortLabel))" }
        return "À retirer : " + items.joined(separator: ", ")
    }

    private func slot(_ photo: SellPhoto, index: Int) -> some View {
        let flag = model.flag(for: photo)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    Text(flag.shortLabel.prefix(1).uppercased() + flag.shortLabel.dropFirst())
                        .font(RF.T.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(RF.C.hibiscus.opacity(0.9))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(flag == nil ? Color.clear : RF.C.hibiscus, lineWidth: 2))
            .overlay(alignment: .bottomLeading) {
                if index == 0 && !photo.isChecking && flag == nil {
                    Text("Couverture")
                        .font(RF.T.caption.weight(.medium))
                        .foregroundStyle(RF.C.text)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.white.opacity(0.92)))
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { model.removePhoto(photo.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(RF.C.ink0.opacity(0.6)))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle(scale: 0.9))
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

    private func accessibilityLabel(_ photo: SellPhoto, index: Int, flag: PhotoFlag?) -> String {
        let base = "Photo \(index + 1)"
        if photo.isChecking { return "\(base), contrôle en cours" }
        if let flag { return "\(base), refusée : \(flag.label)" }
        return index == 0 ? "\(base), couverture, validée" : "\(base), validée"
    }

    private func addSlot(symbol: String, label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 4) {
            Image(systemName: symbol).font(RF.T.title3.weight(.regular))
            Text(label).font(RF.T.caption)
        }
        .foregroundStyle(RF.C.textDim)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(RF.C.card, in: shape)
        .overlay(shape.strokeBorder(RF.C.line, lineWidth: 1))
        .contentShape(shape)
    }
}

private extension PhotoFlag {
    /// One-word version of `label` for the photo tile and the summary line.
    var shortLabel: String {
        switch self {
        case .blur: "floue"
        case .nudity: "contenu sensible"
        case .inappropriate: "inappropriée"
        case .duplicate: "doublon"
        case .screenshot: "capture d'écran"
        case .watermark: "filigrane"
        }
    }
}

/// Section header for the wizard's `Form` steps: one short line, sentence case.
private struct SellFormHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.textDim)
            .textCase(nil)
            .padding(.bottom, 4)
    }
}

// MARK: - 2. Catégorie

struct SellCategoryStep: View {
    @Bindable var model: SellFlowModel

    private var selection: Binding<Gender?> {
        Binding(get: { model.draft.gender },
                set: { if let gender = $0 { model.setGender(gender) } })
    }

    var body: some View {
        Form {
            Section {
                Picker("Catégorie", selection: selection) {
                    ForEach(Gender.allCases) { gender in
                        Label {
                            Text(gender.label).foregroundStyle(RF.C.text)
                        } icon: {
                            Image(systemName: gender.symbol).foregroundStyle(RF.C.textDim)
                        }
                        .tag(Optional(gender))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SellFormHeader("Où ranger cet article ?")
            }
        }
        .formStyle(.grouped)
        .sensoryFeedback(.selection, trigger: model.draft.gender)
    }
}

// MARK: - 3. Marque

struct SellBrandStep: View {
    @Bindable var model: SellFlowModel
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Choisis la marque, ou « Autre ».")
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
                    SellFieldLabel(text: "Marque")
                    TextField("Woodin, Vlisco…", text: $model.draft.brandCustom)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($customFocused)
                        .sellField(focused: customFocused)
                        .accessibilityLabel("Précise la marque")
                        .onSubmit { model.advance() }
                }
                .padding(.top, RF.S.xl)
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
            SellTagline("Type de taille, puis taille.")
            SellFlowLayout {
                ForEach(model.allowedSizeTypes) { type in
                    SellPill(title: typeLabel(type), selected: model.draft.sizeType == type, accent: .ink) {
                        model.setSizeType(type)
                    }
                }
            }
            .padding(.bottom, RF.S.xl)

            if let type = model.draft.sizeType, type != .unique {
                SectionLabel(type == .chaussures ? "Pointure" : "Taille")
                    .padding(.bottom, RF.S.sm)
                SellFlowLayout {
                    ForEach(type.options, id: \.self) { value in
                        SellPill(title: value, selected: model.draft.sizeValue == value, accent: .ink) {
                            model.draft.sizeValue = value
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: model.draft.sizeType)
    }

    private func typeLabel(_ type: SizeType) -> String {
        switch type {
        case .haut: "Haut"
        case .pantalon: "Bas"
        case .chaussures: "Chaussures"
        case .enfant: "Enfant"
        case .unique: "Taille unique"
        }
    }
}

// MARK: - 5. État

struct SellConditionStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        Form {
            Section {
                Picker("État", selection: $model.draft.condition) {
                    ForEach(ItemCondition.allCases) { condition in
                        Text(condition.label)
                            .foregroundStyle(RF.C.text)
                            .tag(Optional(condition))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SellFormHeader("Sois honnête, ça évite les litiges.")
            }
        }
        .formStyle(.grouped)
        .sensoryFeedback(.selection, trigger: model.draft.condition)
    }
}

// MARK: - 6. Couleur

struct SellColorStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Couleur dominante.")
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
            SellTagline("Plus c'est précis, moins on te pose de questions.")

            SellFieldLabel(text: "Titre", counter: "\(model.draft.title.count)/\(SellFlowModel.titleMax)")
            TextField("Robe wax cintrée", text: $model.draft.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focus, equals: .title)
                .sellField(focused: focus == .title)
                .accessibilityLabel("Titre")
                .onSubmit { focus = .description }
                .onChange(of: model.draft.title) { _, new in
                    if new.count > SellFlowModel.titleMax { model.draft.title = String(new.prefix(SellFlowModel.titleMax)) }
                }

            if let suggestion = model.suggestedTitle {
                Button {
                    model.draft.title = suggestion
                    Haptics.selection()
                } label: {
                    Label {
                        Text("Utiliser « \(suggestion) »").lineLimit(1)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                    }
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.hibiscus)
                }
                .buttonStyle(RFPressStyle())
                .padding(.top, RF.S.sm)
                .accessibilityLabel("Utiliser le titre suggéré : \(suggestion)")
            }

            SellFieldLabel(text: "Description (facultatif)",
                           counter: "\(model.draft.description.count)/\(SellFlowModel.descriptionMax)")
                .padding(.top, RF.S.xl)
            TextField("Matière, coupe, nombre de ports…", text: $model.draft.description, axis: .vertical)
                .lineLimit(5...12)
                .focused($focus, equals: .description)
                .sellField(focused: focus == .description)
                .accessibilityLabel("Description")
                .onChange(of: model.draft.description) { _, new in
                    if new.count > SellFlowModel.descriptionMax {
                        model.draft.description = String(new.prefix(SellFlowModel.descriptionMax))
                    }
                }
        }
        .onAppear { if model.draft.title.isEmpty { focus = .title } }
    }
}

// MARK: - 8. Prix

struct SellPriceStep: View {
    @Bindable var model: SellFlowModel
    @State private var priceText = ""
    @FocusState private var priceFocused: Bool

    private var negotiable: Binding<Bool> {
        Binding(get: { model.draft.negotiable },
                set: { on in
                    model.draft.negotiable = on
                    if on { model.clampMinOffer() }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SellTagline("Tu pourras le modifier plus tard.")

            PriceStepper(value: $model.draft.price, step: model.priceStep, range: SellFlowModel.priceRange)
                .frame(maxWidth: .infinity)
                .padding(.top, RF.S.sm)

            HStack(spacing: 8) {
                TextField("Saisir un montant", text: $priceText)
                    .keyboardType(.numberPad)
                    .focused($priceFocused)
                    .font(RF.T.price(.body, weight: .regular))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Prix en FCFA")
                Text("FCFA").font(RF.T.footnote).foregroundStyle(RF.C.textDim)
                    .accessibilityHidden(true)
            }
            .sellField(focused: priceFocused)
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
            .padding(.top, RF.S.md)

            VStack(alignment: .leading, spacing: 0) {
                Toggle("Ouvert aux offres", isOn: negotiable)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .tint(RF.C.hibiscus)
                    .padding(.vertical, 12)

                if model.draft.negotiable {
                    Divider()
                    HStack {
                        Text("Offre minimum").font(RF.T.body).foregroundStyle(RF.C.text)
                        Spacer(minLength: 8)
                        PriceStepper(value: $model.draft.minOffer, step: model.priceStep, range: minOfferRange, compact: true)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Offre minimum acceptée")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, RF.S.lg)
            .rfCard()
            .padding(.top, RF.S.xl)
            .sensoryFeedback(.selection, trigger: model.draft.negotiable)

            if model.draft.negotiable {
                Text("Offre minimum privée, jamais montrée aux acheteuses.")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .padding(.horizontal, RF.S.lg)
                    .padding(.top, 6)
                    .transition(.opacity)
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
}

// MARK: - 9. Livraison

struct SellDeliveryStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        Form {
            Section {
                ForEach(DeliveryMethod.allCases) { method in
                    SellMethodRow(symbol: method.symbol, title: method.label, subtitle: shortSubtitle(method),
                                  trailing: method.fee == 0 ? "Gratuit" : "~\(Fmt.fcfa(method.fee))",
                                  selected: model.draft.delivery.contains(method)) {
                        if model.draft.delivery.contains(method) { model.draft.delivery.remove(method) }
                        else { model.draft.delivery.insert(method) }
                    }
                }
            } header: {
                SellFormHeader("Plusieurs choix possibles.")
            } footer: {
                Text(footer)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        let base = "Frais à la charge de l'acheteuse."
        let cheap = model.draft.price < SellFlowModel.handDeliveryHint
        guard cheap, !model.draft.delivery.contains(.mainPropre) else { return base }
        return base + " Sous \(Fmt.fcfa(SellFlowModel.handDeliveryHint)), pense à la main propre."
    }

    private func shortSubtitle(_ method: DeliveryMethod) -> String {
        switch method {
        case .relais: "Retrait sous 24-48 h"
        case .mainPropre: "Rendez-vous direct"
        case .yango: "Coursier, 30 à 60 min"
        }
    }
}

// MARK: - 10. Relecture

struct SellReviewStep: View {
    @Bindable var model: SellFlowModel

    var body: some View {
        Form {
            Section {
                photos
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                Button { model.edit(.price) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.fcfa(model.draft.price))
                                .font(RF.T.price(.title3))
                                .foregroundStyle(RF.C.text)
                            Text(model.draft.negotiable ? "Ouvert aux offres" : "Prix fixe")
                                .font(RF.T.footnote)
                                .foregroundStyle(RF.C.textDim)
                        }
                        Spacer(minLength: 8)
                        chevron
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Modifier le prix")
                if !model.draft.title.isEmpty {
                    row("Titre", model.draft.title, .details)
                }
            } header: {
                SellFormHeader("Touche une ligne pour la modifier.")
            }

            Section {
                row("Photos", "\(model.photos.count)", .photos)
                row("Catégorie", model.draft.gender?.label ?? "—", .category)
                row("Marque", model.brandLabel, .brand)
                row("Taille", model.sizeLabel, .size)
                row("État", model.draft.condition?.label ?? "—", .condition)
                row("Couleur", model.draft.color ?? "—", .color)
                if model.draft.negotiable {
                    row("Offre minimum", Fmt.fcfa(model.draft.minOffer), .price)
                }
                row("Livraison", deliveryLabel, .delivery)
            }

            if !model.draft.description.isEmpty || !model.draft.defectComment.isEmpty {
                Section("Description") {
                    if !model.draft.description.isEmpty {
                        Button { model.edit(.details) } label: {
                            Text(model.draft.description)
                                .font(RF.T.subheadline)
                                .foregroundStyle(RF.C.text)
                                .lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint("Modifier la description")
                    }
                    if !model.draft.defectComment.isEmpty {
                        Button { model.edit(.photos) } label: {
                            Text("Défauts : \(model.draft.defectComment)")
                                .font(RF.T.subheadline)
                                .foregroundStyle(RF.C.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint("Modifier les défauts")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    RF.C.paperDim
                        .frame(width: index == 0 ? 112 : 84, height: 140)
                        .overlay {
                            if let image = photo.analysis?.thumbnail {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(height: 140)
        .contentShape(Rectangle())
        .onTapGesture { model.edit(.photos) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.photos.count) photos")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Modifier les photos")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim.opacity(0.6))
    }

    private var deliveryLabel: String {
        let labels = DeliveryMethod.allCases.filter { model.draft.delivery.contains($0) }.map { method -> String in
            switch method {
            case .relais: "Point relais"
            case .mainPropre: "Main propre"
            case .yango: "Yango"
            }
        }
        return labels.isEmpty ? "Non précisé" : labels.joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String, _ step: SellFlowModel.Step) -> some View {
        Button { model.edit(step) } label: {
            HStack(spacing: 8) {
                Text(label).foregroundStyle(RF.C.text)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                chevron
            }
            .font(RF.T.body)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(label) : \(value)")
        .accessibilityHint("Modifier")
    }
}
