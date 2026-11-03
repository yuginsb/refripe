import SwiftUI
import PhotosUI
import UIKit

// Steps 1 (Photos) and 2 (L'article) of the v3 sell wizard. Steps 3–4: SellPriceReviewSteps.swift.

// MARK: - 1. Photos

struct SellPhotosStep: View {
    @Bindable var model: SellFlowModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @FocusState private var defectFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    slot(photo, index: index)
                }
                if model.remainingPhotoSlots > 0 {
                    if SellCameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            addSlot(symbol: "camera", label: "Photo")
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Prendre une photo")
                    }
                    // « + » tiles complete the last row of the grid (at least one).
                    ForEach(0..<addTileCount, id: \.self) { index in
                        PhotosPicker(selection: $pickerItems,
                                     maxSelectionCount: model.remainingPhotoSlots,
                                     selectionBehavior: .ordered,
                                     matching: .images,
                                     preferredItemEncoding: .current) {
                            addSlot(symbol: "plus", label: index == 0 ? "Ajouter" : nil)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Ajouter des photos")
                        .accessibilityIdentifier(index == 0 ? "sell.photos.add" : "sell.photos.add.\(index)")
                    }
                }
            }
            .padding(.bottom, RF.S.sm)

            HStack(alignment: .firstTextBaseline) {
                if !model.flaggedPhotos.isEmpty {
                    Label(flagSummary, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(RF.C.hibiscusText)
                }
                Spacer(minLength: 8)
                Text("\(model.photos.count)/\(Catalog.sellPhotoMax)")
                    .monospacedDigit()
                    .foregroundStyle(RF.C.textDim)
            }
            .font(RF.T.footnote)
            .padding(.bottom, RF.S.xl)
            .accessibilityElement(children: .combine)

            SellFieldLabel(text: "Défauts",
                           counter: model.draft.defectComment.isEmpty ? nil
                               : "\(model.draft.defectComment.count)/\(SellFlowModel.defectMax)")
            TextField("Tache, trou…", text: $model.draft.defectComment, axis: .vertical)
                .lineLimit(2...6)
                .focused($defectFocused)
                .sellField(focused: defectFocused)
                .accessibilityLabel("Défauts")
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

    /// Number of « + » tiles: fill the current row of 3, at least one, never more than the free slots.
    private var addTileCount: Int {
        let used = model.photos.count + (SellCameraPicker.isAvailable ? 1 : 0)
        let fill = (3 - (used % 3)) % 3
        return min(model.remainingPhotoSlots, max(1, fill))
    }

    /// "Photo 2 floue, photo 3 en double".
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
                        .foregroundStyle(RF.C.onAccent)
                        .lineLimit(1)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(RF.C.hibiscus)
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
                        .background(Capsule().fill(RF.C.card.opacity(0.92)))
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { model.removePhoto(photo.id) } label: {
                    Image(systemName: "xmark")
                        .font(RF.T.caption.weight(.bold))
                        .foregroundStyle(RF.C.textOnInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(RF.C.ink0.opacity(0.6)))
                        .frame(width: 44, height: 44)   // tap target
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

    private func addSlot(symbol: String, label: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        // Shapes are greedy: the tile takes the full grid cell width, then stays square.
        return shape
            .fill(RF.C.card)
            .overlay(shape.strokeBorder(RF.C.line, lineWidth: 1))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: symbol).font(RF.T.title3.weight(.regular))
                    if let label { Text(label).font(RF.T.caption) }
                }
                .foregroundStyle(RF.C.textDim)
            }
            .aspectRatio(1, contentMode: .fit)
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
struct SellFormHeader: View {
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


// MARK: - 2. L'article

/// Type d'article, Pour, Taille (grid derived from the type), État, then Marque and Couleur (optional).
struct SellArticleStep: View {
    @Bindable var model: SellFlowModel
    @FocusState private var brandFocused: Bool

    private var gender: Binding<Gender?> {
        Binding(get: { model.draft.gender },
                set: { if let g = $0 { model.setGender(g) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RF.S.xl) {
            group("Type") {
                SellFlowLayout {
                    ForEach(ItemType.allCases) { type in
                        SellPill(title: type.label, selected: model.draft.itemType == type) {
                            model.setItemType(type)
                        }
                        .accessibilityIdentifier("sell.itemType.\(type.rawValue)")
                    }
                }
            }

            group("Pour") {
                Picker("Pour", selection: gender) {
                    ForEach(Gender.allCases) { g in
                        Text(g.label).tag(Optional(g))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sell.gender")
            }

            if let grid = model.resolvedSizeType {
                group(grid == .chaussures ? "Pointure" : "Taille") {
                    SellFlowLayout {
                        if grid != .unique {
                            ForEach(grid.options, id: \.self) { value in
                                SellPill(title: value,
                                         selected: model.draft.sizeType == grid && model.draft.sizeValue == value) {
                                    model.selectSize(value)
                                }
                                .accessibilityIdentifier("sell.size.\(value)")
                            }
                        }
                        SellPill(title: "Taille unique", selected: model.draft.sizeType == .unique) {
                            model.selectOneSize()
                        }
                        .accessibilityIdentifier("sell.size.unique")
                    }
                }
                .transition(.opacity)
            }

            group("État") {
                VStack(spacing: 0) {
                    ForEach(Array(ItemCondition.allCases.enumerated()), id: \.element) { index, condition in
                        if index > 0 { Divider().overlay(RF.C.line).padding(.leading, RF.S.lg) }
                        conditionRow(condition)
                    }
                }
                .rfCard()
            }

            group("Marque") {
                TextField("Facultatif", text: $model.brandText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($brandFocused)
                    .sellField(focused: brandFocused)
                    .accessibilityLabel("Marque")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Catalog.brands, id: \.self) { brand in
                            SellPill(title: brand, selected: model.draft.brand == brand) {
                                model.brandText = model.draft.brand == brand ? "" : brand
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(.top, RF.S.sm)
            }

            group("Couleur") {
                SellFlowLayout {
                    ForEach(Catalog.colors, id: \.self) { color in
                        SellPill(title: color, selected: model.draft.color == color,
                                 swatch: SellColorSwatch.style(for: color)) {
                            model.draft.color = model.draft.color == color ? nil : color
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: model.resolvedSizeType)
        .sensoryFeedback(.selection, trigger: model.draft.condition)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            SectionLabel(title)
            content()
        }
    }

    private func conditionRow(_ condition: ItemCondition) -> some View {
        let selected = model.draft.condition == condition
        return Button { model.draft.condition = condition } label: {
            HStack {
                Text(condition.label)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(RF.T.body.weight(.semibold))
                    .foregroundStyle(RF.C.hibiscusText)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, RF.S.lg)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(condition.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sell.condition.\(condition.rawValue)")
    }
}
