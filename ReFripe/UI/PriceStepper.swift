import SwiftUI

/// −/+ amount stepper: large tabular price between two round tinted buttons. Long-press repeats; VoiceOver adjustable.
struct PriceStepper: View {
    @Binding var value: FCFA
    var step: FCFA
    var range: ClosedRange<FCFA>
    var compact: Bool

    init(value: Binding<FCFA>, step: FCFA, range: ClosedRange<FCFA>, compact: Bool = false) {
        self._value = value
        self.step = max(1, step)
        self.range = range
        self.compact = compact
    }

    private var canDecrement: Bool { value > range.lowerBound }
    private var canIncrement: Bool { value < range.upperBound }

    private func decrement() { value = max(range.lowerBound, min(range.upperBound, value - step)) }
    private func increment() { value = min(range.upperBound, max(range.lowerBound, value + step)) }

    var body: some View {
        HStack(spacing: compact ? 8 : 16) {
            stepButton("minus", label: "Diminuer", enabled: canDecrement, perform: decrement)
            Text(Fmt.fcfa(value))
                .font(compact ? RF.T.price(.body) : RF.T.price(.largeTitle, weight: .bold))
                .foregroundStyle(RF.C.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.2), value: value)
                .frame(minWidth: compact ? 96 : 170)
            stepButton("plus", label: "Augmenter", enabled: canIncrement, perform: increment)
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Montant")
        .accessibilityValue(Fmt.fcfa(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        let side: CGFloat = compact ? 32 : 44
        return Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 13 : 17, weight: .medium))
                .foregroundStyle(RF.C.hibiscus)
                .frame(width: side, height: side)
                .background(Circle().fill(RF.C.hibiscus.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(RFPressStyle(scale: 0.92))
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

private struct PriceStepperDemo: View {
    @State private var amount: FCFA = 7_500
    @State private var floorAmount: FCFA = 0

    var body: some View {
        VStack(spacing: 30) {
            PriceStepper(value: $amount, step: 500, range: 4_000...9_500)
            PriceStepper(value: $floorAmount, step: 500, range: 0...15_000, compact: true)
        }
        .padding()
        .rfScreenBackground()
    }
}

struct PriceStepper_Previews: PreviewProvider {
    static var previews: some View {
        PriceStepperDemo()
    }
}
