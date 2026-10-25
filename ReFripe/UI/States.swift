import SwiftUI

/// Empty state: native `ContentUnavailableView` (icon, title, one line, optional action), tinted hibiscus.
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
        ContentUnavailableView {
            Label(title, systemImage: symbol)
                .foregroundStyle(RF.C.text)
        } description: {
            Text(message)
                .foregroundStyle(RF.C.textDim)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(RF.T.button)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(RF.C.hibiscus)
            }
        }
        .padding(.vertical, RF.S.xl)
        .frame(maxWidth: .infinity)
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
                Text(message).font(RF.T.footnote).foregroundStyle(RF.C.textDim)
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
                       title: "Ça n'a pas marché",
                       message: error.localizedDescription,
                       actionTitle: retry == nil ? nil : "Réessayer",
                       action: retry)
    }
}

struct States_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            EmptyStateView(symbol: "heart", title: "Pas encore d'envies",
                           message: "Touche le cœur d'un article pour le retrouver ici.",
                           actionTitle: "Découvrir") {}
            ErrorStateView(error: RepositoryError.network("délai dépassé")) {}
            LoadingView("Chargement…").frame(height: 120)
        }
        .rfScreenBackground()
    }
}
