import SwiftUI
import UIKit

/// Dark pill toast, SF subheadline, no glow.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(RF.T.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Capsule().fill(RF.C.ink1.opacity(0.95)))
            .padding(.horizontal, 24)
    }
}

private struct ToastHost: ViewModifier {
    @Environment(AppStore.self) private var store
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let message = store.toast {
                    ToastView(message: message)
                        .id(message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
                }
            }
            .padding(.bottom, bottomPadding)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Renders `store.toast` as a pill at the bottom. RootView installs it above the tab bar and inside
    /// full-screen covers; features don't need to add it.
    func rfToastHost(bottomPadding: CGFloat = 16) -> some View {
        modifier(ToastHost(bottomPadding: bottomPadding))
    }
}
