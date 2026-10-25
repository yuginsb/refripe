import SwiftUI
import UIKit

/// "Vendre" — 10-step listing wizard presented full screen by `MainTabView` (`router.isSellPresented`).
/// Mockup `screenSell` + `sellStep*`; quality control of photos happens on-device before step 2.
struct SellFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var model = SellFlowModel()
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            Group {
                if let listing = model.published {
                    SellSuccessView(model: model, listing: listing, close: close)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    wizard
                }
            }
            .rfScreenBackground()
        }
        .tint(RF.C.hibiscus)
        .onAppear { model.notify = { store.show($0) } }
    }

    // MARK: Wizard

    private var wizard: some View {
        Group {
            if model.step.usesForm {
                // Form steps (category, condition, delivery, review) scroll themselves.
                stepContent
            } else {
                ScrollView {
                    stepContent
                        .padding(.horizontal, RF.S.gutter)
                        .padding(.top, RF.S.lg)
                        .padding(.bottom, RF.S.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .id(model.step)
        .transition(.asymmetric(
            insertion: .move(edge: model.movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity))
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { progressBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle(model.step.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { hideKeyboard() }.fontWeight(.semibold)
            }
        }
        .confirmationDialog("Abandonner cette annonce ?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Abandonner l'annonce", role: .destructive) { close() }
            Button("Continuer à remplir", role: .cancel) {}
        } message: {
            Text("Tes photos et infos seront perdues.")
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .photos: SellPhotosStep(model: model)
        case .category: SellCategoryStep(model: model)
        case .brand: SellBrandStep(model: model)
        case .size: SellSizeStep(model: model)
        case .condition: SellConditionStep(model: model)
        case .color: SellColorStep(model: model)
        case .details: SellDetailsStep(model: model)
        case .price: SellPriceStep(model: model)
        case .delivery: SellDeliveryStep(model: model)
        case .review: SellReviewStep(model: model)
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.step.previous != nil {
                Button { hideKeyboard(); model.back() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                .accessibilityLabel("Étape précédente")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { requestClose() } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Fermer")
        }
    }

    /// Thin native progress bar under the navigation bar.
    private var progressBar: some View {
        let fraction = Double(model.step.rawValue) / Double(SellFlowModel.Step.allCases.count)
        return ProgressView(value: fraction)
            .progressViewStyle(.linear)
            .tint(RF.C.hibiscus)
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, 6)
            .background(RF.C.paper)
            .animation(.snappy, value: model.step)
            .accessibilityElement()
            .accessibilityLabel("Progression")
            .accessibilityValue("Étape \(model.step.rawValue) sur \(SellFlowModel.Step.allCases.count) : \(model.step.title)")
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let hint = model.blockingHint {
                Text(hint)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            RFButton(primaryTitle, isLoading: model.isPublishing) {
                primaryAction()
            }
            .disabled(!model.canContinue(model.step))
        }
        .padding(.horizontal, RF.S.gutter)
        .padding(.top, RF.S.md)
        .padding(.bottom, RF.S.sm)
        .background(RF.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
        .animation(.easeOut(duration: 0.2), value: model.blockingHint)
    }

    private var primaryTitle: String {
        if model.step == .review { return model.isPublishing ? "Publication…" : "Publier" }
        return model.returnToReview ? "Revenir au récapitulatif" : "Continuer"
    }

    private func primaryAction() {
        hideKeyboard()
        if model.step == .review {
            Task { await model.publish(using: store) }
        } else {
            model.advance()
        }
    }

    // MARK: Closing

    private func requestClose() {
        hideKeyboard()
        if model.isDirty && model.published == nil { confirmClose = true } else { close() }
    }

    private func close() {
        router.isSellPresented = false
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension SellFlowModel.Step {
    /// Steps rendered as a native inset-grouped `Form` instead of a scrolling stack.
    var usesForm: Bool {
        switch self {
        case .category, .condition, .delivery, .review: true
        default: false
        }
    }
}

#Preview {
    SellFlowView().previewEnvironment()
}
