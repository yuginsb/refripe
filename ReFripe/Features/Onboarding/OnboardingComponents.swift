import SwiftUI

// Building blocks shared by the sign-up / onboarding steps and the profile preference editors.
// (Agent D — Features/Onboarding, Features/Profile, Features/Dashboard.)

// MARK: - Wrapping layout (mockup `.size-chips`, `.brand-chips`: flex-wrap)

/// Lays children out left to right and wraps to a new line when the width runs out.
struct OnboardingWrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Progress dots (mockup `.onb-progress` / `.onb-dot`)

struct OnboardingProgressDots: View {
    let count: Int
    /// 0-based index of the current step.
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? RF.C.hibiscus : RF.C.line)
                    .frame(width: 24, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(current + 1) sur \(count)")
    }
}

// MARK: - Tagline (mockup `.auth-tagline`)

struct OnboardingTagline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Category card (mockup `.category-card`)

struct CategoryChoiceCard: View {
    let gender: Gender
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: gender.symbol)
                    .font(RF.T.title3.weight(.regular))
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.textDim)
                    .frame(height: 28)
                Text(gender.label)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .background(selected ? RF.C.hibiscus.opacity(0.08) : RF.C.card, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.hibiscus.opacity(0.6) : RF.C.line, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.hibiscus)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle())
        .animation(.snappy(duration: 0.2), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(gender.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Choice chip (subtle capsule, hibiscus tint when selected; `tone` kept for compatibility)

struct ChoiceChip: View {
    enum Tone { case ink, marigold }

    let title: String
    let selected: Bool
    var tone: Tone = .ink
    var accessibilityText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RF.T.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? RF.C.hibiscus.opacity(0.10) : RF.C.card))
                .overlay(Capsule().strokeBorder(selected ? RF.C.hibiscus.opacity(0.5) : RF.C.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(accessibilityText ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Skip link + primary button row (mockup `.onb-actions`)

struct OnboardingActions: View {
    var skipTitle: String = "Passer"
    let skip: () -> Void
    let primaryTitle: String
    var isLoading: Bool = false
    let primary: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: skip) {
                Text(skipTitle)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.textDim)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.plain)
            RFButton(primaryTitle, isLoading: isLoading, action: primary)
        }
    }
}

// MARK: - Text field (mockup `.field`)

struct OnboardingField<Content: View, Trailing: View>: View {
    let label: String
    let content: Content
    let trailing: Trailing

    init(_ label: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
                trailing
            }
            .accessibilityElement(children: .combine)
            content
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
                .tint(RF.C.hibiscus)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(minHeight: 50)
                .background(RF.C.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1))
        }
    }
}

extension OnboardingField where Trailing == EmptyView {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(label, content: content, trailing: { EmptyView() })
    }
}

/// Small tag next to a field label ("Facultatif", "Disponible").
struct FieldTag: View {
    let text: String
    var ok: Bool = false

    var body: some View {
        Text(text)
            .font(RF.T.caption)
            .foregroundStyle(ok ? RF.C.moneyDeep : RF.C.textDim)
    }
}

// MARK: - Size rows (shared by onboarding and the profile editor)

/// Size fields asked during onboarding (mockup `sizeFields`).
enum OnboardingSizeFields {
    static let types: [SizeType] = [.haut, .pantalon, .chaussures]
}

struct SizePreferenceRows: View {
    @Binding var sizes: [SizeType: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(OnboardingSizeFields.types) { type in
                VStack(alignment: .leading, spacing: 8) {
                    Text(type.label)
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .accessibilityAddTraits(.isHeader)
                    OnboardingWrapLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(type.options, id: \.self) { option in
                            ChoiceChip(title: option, selected: sizes[type] == option,
                                       accessibilityText: type.displayLabel(for: option)) {
                                if sizes[type] == option { sizes[type] = nil } else { sizes[type] = option }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BrandPreferenceChips: View {
    @Binding var brands: Set<String>

    var body: some View {
        OnboardingWrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Catalog.brands, id: \.self) { brand in
                ChoiceChip(title: brand, selected: brands.contains(brand), tone: .marigold) {
                    if brands.contains(brand) { brands.remove(brand) } else { brands.insert(brand) }
                }
            }
        }
    }
}

struct CategoryPreferenceGrid: View {
    @Binding var categories: Set<Gender>

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Gender.allCases) { g in
                CategoryChoiceCard(gender: g, selected: categories.contains(g)) {
                    if categories.contains(g) { categories.remove(g) } else { categories.insert(g) }
                }
            }
        }
    }
}

private struct OnboardingComponentsDemo: View {
    @State private var sizes: [SizeType: String] = [.haut: "M"]
    @State private var brands: Set<String> = ["Nike"]
    @State private var cats: Set<Gender> = [.femme]
    @State private var name = "Aïcha"

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingProgressDots(count: 3, current: 1)
                OnboardingField("Prénom") { TextField("Prénom", text: $name) }
                CategoryPreferenceGrid(categories: $cats)
                SizePreferenceRows(sizes: $sizes)
                BrandPreferenceChips(brands: $brands)
                OnboardingActions(skip: {}, primaryTitle: "Continuer", primary: {})
            }
            .padding(16)
        }
        .rfScreenBackground()
    }
}

#Preview {
    OnboardingComponentsDemo().previewEnvironment()
}
