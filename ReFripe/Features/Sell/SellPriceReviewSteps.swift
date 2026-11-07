import SwiftUI
import UIKit

// Steps 3 (Ton prix) and 4 (Remise + relecture) of the v3 sell wizard.

// MARK: - 3. Ton prix

/// Empty price field (numeric keyboard), similar-price range, « Ouvert aux offres » (on by default),
/// private minimum offer, and the green « Tu recevras » card.
struct SellPriceStep: View {
    @Bindable var model: SellFlowModel
    @Environment(AppStore.self) private var store
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $priceText)
                    .keyboardType(.numberPad)
                    .focused($priceFocused)
                    .font(RF.T.price(.largeTitle, weight: .bold))
                    .foregroundStyle(RF.C.text)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Prix en FCFA")
                    .accessibilityIdentifier("sell.price")
                Text("FCFA")
                    .font(RF.T.title3)
                    .foregroundStyle(RF.C.textDim)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, RF.S.md)
            .padding(.horizontal, RF.S.lg)
            .rfCard()
            .contentShape(Rectangle())
            .onTapGesture { priceFocused = true }

            Text(rangeText)
                .font(RF.T.footnote.monospacedDigit())
                .foregroundStyle(RF.C.textDim)
                .padding(.top, RF.S.sm)
                .padding(.horizontal, RF.S.xs)

            VStack(alignment: .leading, spacing: 0) {
                Toggle("Ouvert aux offres", isOn: negotiable)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .tint(RF.C.hibiscus)
                    .padding(.vertical, 12)

                if model.draft.negotiable && model.draft.price > 0 {
                    Divider().overlay(RF.C.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Offre min.").font(RF.T.body).foregroundStyle(RF.C.text)
                            Text("Privée").font(RF.T.caption).foregroundStyle(RF.C.textDim)
                        }
                        Spacer(minLength: 8)
                        PriceStepper(value: $model.draft.minOffer, step: model.priceStep,
                                     range: model.minOfferRange, compact: true)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Offre minimum, privée")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, RF.S.lg)
            .rfCard()
            .padding(.top, RF.S.xl)
            .sensoryFeedback(.selection, trigger: model.draft.negotiable)

            if model.draft.price > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu recevras \(Fmt.fcfa(model.draft.price))")
                        .font(RF.T.price(.headline))
                        .foregroundStyle(RF.C.moneyDeep)
                    Text("hors commission")
                        .font(RF.T.caption)
                        .foregroundStyle(RF.C.moneyDeep.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RF.S.lg)
                .background(RF.C.moneyTint, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                .padding(.top, RF.S.xl)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: model.draft.negotiable)
        .animation(.snappy, value: model.draft.price > 0)
        .task(id: model.draft.itemType) { await model.loadSimilarPrices(repo: store.repo) }
        .onAppear {
            priceText = model.draft.price > 0 ? String(model.draft.price) : ""
            if model.draft.price == 0 { priceFocused = true }
        }
        .onChange(of: priceText) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(7))
            if digits != new { priceText = digits; return }
            model.setPrice(Int(digits) ?? 0)
        }
    }

    private var rangeText: String {
        if let r = model.similarPriceRange {
            return r.lowerBound == r.upperBound
                ? "Similaires : ~\(Fmt.fcfa(r.lowerBound))"
                : "Similaires : \(Fmt.number(r.lowerBound)) – \(Fmt.fcfa(r.upperBound))"
        }
        return "Souvent : 1 500 – 10 000 FCFA"
    }
}

// MARK: - 4. Remise + relecture

/// Delivery toggles, title / description, then a summary where each row reopens its step.
struct SellReviewStep: View {
    @Bindable var model: SellFlowModel
    private enum Field { case title, description }
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            Group {
            Section {
                ForEach(DeliveryMethod.allCases) { method in
                    SellMethodRow(symbol: method.symbol, title: shortLabel(method), subtitle: shortSubtitle(method),
                                  trailing: method.fee == 0 ? "Gratuit" : Fmt.fcfa(method.fee),
                                  selected: model.draft.delivery.contains(method)) {
                        if model.draft.delivery.contains(method) { model.draft.delivery.remove(method) }
                        else { model.draft.delivery.insert(method) }
                    }
                    .accessibilityIdentifier("sell.delivery.\(method.rawValue)")
                }
            } header: {
                SellFormHeader("Remise")
            } footer: {
                Text("Payé par l'acheteuse")
            }

            Section {
                TextField("Titre", text: $model.draft.title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focus, equals: .title)
                    .accessibilityLabel("Titre")
                    .accessibilityIdentifier("sell.title")
                    .onSubmit { focus = .description }
                    .onChange(of: model.draft.title) { _, new in
                        if new.count > SellFlowModel.titleMax { model.draft.title = String(new.prefix(SellFlowModel.titleMax)) }
                    }
                TextField("Description", text: $model.draft.description, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focus, equals: .description)
                    .accessibilityLabel("Description")
                    .onChange(of: model.draft.description) { _, new in
                        if new.count > SellFlowModel.descriptionMax {
                            model.draft.description = String(new.prefix(SellFlowModel.descriptionMax))
                        }
                    }
            } header: {
                SellFormHeader("Annonce")
            }

            Section {
                photos
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                row("Article", model.articleLabel.isEmpty ? "—" : model.articleLabel, .article)
                row("Taille", model.sizeLabel, .article)
                row("État", model.draft.condition?.label ?? "—", .article)
                if !model.brandLabel.isEmpty && model.brandLabel != "—" {
                    row("Marque", model.brandLabel, .article)
                }
                if let color = model.draft.color {
                    row("Couleur", color, .article)
                }
                row("Prix", model.draft.price > 0 ? Fmt.fcfa(model.draft.price) : "—", .price)
                if model.draft.negotiable {
                    row("Offre min.", model.draft.minOffer > 0 ? Fmt.fcfa(model.draft.minOffer) : "—", .price)
                }
                if !model.draft.defectComment.isEmpty {
                    row("Défauts", model.draft.defectComment, .photos)
                }
            } header: {
                SellFormHeader("Relecture")
            }
                    }
            .listRowBackground(RF.C.card)
        }
        .formStyle(.grouped)
    }

    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    RF.C.paperDim
                        .frame(width: index == 0 ? 96 : 72, height: 120)
                        .overlay {
                            if let image = photo.analysis?.thumbnail {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(height: 120)
        .contentShape(Rectangle())
        .onTapGesture { model.edit(.photos) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.photos.count) photos")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Modifier les photos")
    }

    private func shortLabel(_ method: DeliveryMethod) -> String {
        switch method {
        case .relais: "Point relais"
        case .mainPropre: "Main propre"
        case .yango: "Yango"
        }
    }

    private func shortSubtitle(_ method: DeliveryMethod) -> String {
        switch method {
        case .relais: "24-48 h"
        case .mainPropre: "Rendez-vous"
        case .yango: "30-60 min"
        }
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
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim.opacity(0.6))
            }
            .font(RF.T.body)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(label) : \(value)")
        .accessibilityHint("Modifier")
    }
}
