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
                    .fill(i < current ? RF.C.money : (i == current ? RF.C.hibiscus : RF.C.line))
                    .frame(width: 22, height: 4)
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
            .font(RF.F.body(12))
            .foregroundStyle(RF.C.textDim)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Category card (mockup `.category-card`)

struct CategoryChoiceCard: View {
    let gender: Gender
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: gender.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.text)
                    .frame(height: 30)
                Text(gender.label)
                    .font(RF.F.body(12, .bold))
                    .foregroundStyle(RF.C.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 10)
            .background(selected ? RF.C.hibiscus.opacity(0.08) : RF.C.card, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.hibiscus : RF.C.line, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(RF.C.hibiscus)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
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

// MARK: - Choice chip (mockup `.size-chip` → ink when active, `.brand-chip` → marigold when active)

struct ChoiceChip: View {
    enum Tone { case ink, marigold }

    let title: String
    let selected: Bool
    var tone: Tone = .ink
    var accessibilityText: String? = nil
    let action: () -> Void

    private var activeBg: Color { tone == .ink ? RF.C.ink1 : RF.C.marigold }
    private var activeFg: Color { tone == .ink ? RF.C.paper : RF.C.ink0 }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RF.F.body(12, .bold))
                .lineLimit(1)
                .foregroundStyle(selected ? activeFg : RF.C.text)
                .padding(.vertical, tone == .ink ? 8 : 9)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? activeBg : RF.C.card))
                .overlay(Capsule().strokeBorder(selected ? activeBg : RF.C.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(RFPressStyle(scale: 0.94))
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
                    .font(RF.F.body(12, .bold))
                    .underline()
                    .foregroundStyle(RF.C.textDim)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
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
                Text(label.uppercased())
                    .font(RF.F.body(10.5, .bold))
                    .kerning(0.42)
                    .foregroundStyle(RF.C.textDim)
                trailing
            }
            .accessibilityElement(children: .combine)
            content
                .font(RF.F.body(13))
                .foregroundStyle(RF.C.text)
                .tint(RF.C.hibiscus)
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(RF.C.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1.5))
        }
    }
}

extension OnboardingField where Trailing == EmptyView {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(label, content: content, trailing: { EmptyView() })
    }
}

/// Small pill next to a field label (mockup `.field-tag` / `.field-tag.ok`).
struct FieldTag: View {
    let text: String
    var ok: Bool = false

    var body: some View {
        Text(text)
            .font(RF.F.body(9, .bold))
            .foregroundStyle(ok ? RF.C.moneyDeep : RF.C.textDim)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(Capsule().fill(ok ? RF.C.money.opacity(0.14) : RF.C.paperDim))
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
                        .font(RF.F.body(11.5, .bold))
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
