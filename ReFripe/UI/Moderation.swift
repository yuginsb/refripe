import SwiftUI
import UIKit

// v3 — shared moderation & support pieces: « Signaler » sheet, support WhatsApp, legal links.

// MARK: - Constants

/// Support contact. TODO: replace the placeholder with the real WhatsApp Business number (international, digits only).
enum Support {
    static let whatsAppNumber = "[NUMERO_SUPPORT]"
    static let defaultMessage = "Bonjour ReFripe, j'ai besoin d'aide."

    /// `https://wa.me/<digits>?text=…`, or nil while the number isn't configured (placeholder / too short).
    static func whatsAppURL(message: String = defaultMessage) -> URL? {
        let digits = whatsAppNumber.filter(\.isNumber)
        guard digits.count >= 8, digits.count == whatsAppNumber.filter({ !$0.isWhitespace && $0 != "+" }).count else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        return components.url
    }
}

/// Public legal pages (to publish on refripe.app).
enum Legal {
    static let termsURL = URL(string: "https://refripe.app/cgu")!
    static let privacyURL = URL(string: "https://refripe.app/confidentialite")!
}

// MARK: - WhatsApp support

/// Opens the support WhatsApp conversation; shows an alert while the number isn't configured.
/// Use as a `List`/`Form` row or anywhere a plain button fits: `SupportWhatsAppButton("Aide sur WhatsApp")`.
struct SupportWhatsAppButton<Label: View>: View {
    private let label: Label
    @Environment(\.openURL) private var openURL
    @State private var showUnavailable = false

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        Button(action: open) { label }
            .alert("Support indisponible", isPresented: $showUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Numéro pas encore configuré.")
            }
    }

    private func open() {
        guard let url = Support.whatsAppURL() else {
            showUnavailable = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showUnavailable = true }
        }
    }
}

extension SupportWhatsAppButton where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImage: String = "message") {
        self.init { SwiftUI.Label(title, systemImage: systemImage) }
    }
}

// MARK: - Report sheet

/// « Signaler » sheet: reason (inline list), optional details, « Envoyer ».
/// `onSubmit` performs the repository call (`repo.report(listingId:userId:reason:details:)`); errors are shown as a toast
/// and keep the sheet open, success closes it with a confirmation toast.
///
///     .sheet(isPresented: $reporting) {
///         ReportReasonSheet(subject: "cette annonce") { reason, details in
///             try await store.repo.report(listingId: id, userId: nil, reason: reason, details: details)
///         }
///     }
struct ReportReasonSheet: View {
    /// What is reported, used in the title: "cette annonce", "ce membre".
    let subject: String
    let onSubmit: (ReportReason, String) async throws -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isSending = false

    init(subject: String, onSubmit: @escaping (ReportReason, String) async throws -> Void) {
        self.subject = subject
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    Picker("Motif", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in
                            Text(r.label).foregroundStyle(RF.C.text).tag(Optional(r))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Motif").textCase(nil)
                }
                Section {
                    TextField("Détails", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Détails du signalement")
                }
                            }
                .listRowBackground(RF.C.card)
            }
            .font(RF.T.body)
            .rfScreenBackground()
            .navigationTitle("Signaler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Envoyer") { Task { await send() } }
                            .disabled(reason == nil)
                    }
                }
            }
        }
        .tint(RF.C.hibiscus)
        .sensoryFeedback(.selection, trigger: reason)
    }

    private func send() async {
        guard let reason, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await onSubmit(reason, details.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            store.show("Signalement envoyé")
            dismiss()
        } catch {
            store.show(error)
        }
    }
}

struct Moderation_Previews: PreviewProvider {
    static var previews: some View {
        ReportReasonSheet(subject: "cette annonce") { _, _ in }
            .previewEnvironment()
    }
}
