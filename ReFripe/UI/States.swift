import SwiftUI

/// Empty state (mockup `.empty-state`): faded house motif, icon, title, message, optional action.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(RF.C.textDim.opacity(0.5))
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(title)
                .font(RF.F.display(15))
                .foregroundStyle(RF.C.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text(message)
                .font(RF.F.body(12.5))
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle, let action {
                RFButton(actionTitle, style: .primary, action: action)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 54)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            MotifPattern()
                .frame(width: 150, height: 150)
                .mask {
                    RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: 75)
                }
                .opacity(0.75)
                .padding(.top, 30)
        }
    }
}

/// Centered spinner for screen-level loading.
struct LoadingView: View {
    var message: String?

    init(_ message: String? = nil) { self.message = message }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(RF.C.hibiscus)
            if let message {
                Text(message).font(RF.F.body(12.5)).foregroundStyle(RF.C.textDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Chargement")
    }
}

/// Screen-level error with an optional retry.
struct ErrorStateView: View {
    let error: Error
    var retry: (() -> Void)?

    init(error: Error, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    var body: some View {
        EmptyStateView(symbol: "wifi.exclamationmark",
                       title: "Oups, ça n'a pas marché",
                       message: error.localizedDescription,
                       actionTitle: retry == nil ? nil : "Réessayer",
                       action: retry)
    }
}

struct States_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            EmptyStateView(symbol: "heart", title: "Pas encore d'envies",
                           message: "Swipe à droite ou touche le cœur d'un article pour le retrouver ici.",
                           actionTitle: "Découvrir") {}
            ErrorStateView(error: RepositoryError.network("délai dépassé")) {}
            LoadingView("Chargement…").frame(height: 120)
        }
        .rfScreenBackground()
    }
}
