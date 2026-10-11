import XCTest

/// Walks the main flow of the demo app and attaches a screenshot of every screen
/// (`XCTAttachment`, kept always). CI exports them from the .xcresult to the `ci-screens` branch.
///
/// Launch argument `-uiTestingSignedOut` makes the demo start signed out so the sign-up flow is shown;
/// the test signs back in as Awa (demo phone 07 07 07 07 07, code 1234).
/// A missing element records a failure but the walk goes on (`continueAfterFailure = true`).
@MainActor
final class MainFlowScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let timeout: TimeInterval = 15

    func testMainFlowScreenshots() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-uiTestingSignedOut"]
        // System alerts (e.g. notification permission) must not block the walk.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Autoriser", "Allow", "OK", "Ne pas autoriser", "Don’t Allow", "Don't Allow"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app.launch()

        step("00 sign-up") { signUp() }
        step("01 discover swipe") { discoverSwipe() }
        step("02 discover grid") { discoverGrid() }
        step("03 filter sheet") { filterSheet() }
        step("04 product") { product() }
        step("05 offer composer") { offerComposer() }
        step("06 checkout") { checkout() }
        step("07 wishlist") { wishlist() }
        step("08 sell") { sell() }
        step("09 messages") { messages() }
        step("10 chat") { chat() }
        step("11 profile") { profile() }
        step("12 dashboard") { dashboard() }
        step("13 notifications") { notifications() }
    }

    // MARK: - Steps

    private func signUp() {
        let phoneButton = button("Continuer avec mon numéro")
        guard phoneButton.waitForExistence(timeout: timeout) else {
            // Onboarding not shown (already signed in): nothing to do.
            snap("00-onboarding-skipped")
            return
        }
        snap("00-signup-start")
        phoneButton.tap()

        let phone = app.textFields["Numéro mobile"]
        guard require(phone, "phone field") else { return }
        phone.tap()
        phone.typeText("0707070707")
        snap("00-signup-phone")

        let send = button("Recevoir le code")
        guard require(send, "Recevoir le code") else { return }
        send.tap()

        guard require(button("Valider"), "OTP screen") else { return }
        // The hidden code field gets the focus as soon as the code is sent.
        _ = app.textFields["Code de vérification à 4 chiffres"].waitForExistence(timeout: 5)
        app.typeText("1234")   // 4 digits → verifies automatically

        // Signed back in as Awa (onboarding already completed) → the cover closes on the tab bar.
        if !app.tabBars.firstMatch.waitForExistence(timeout: timeout) {
            let validate = button("Valider")
            if validate.exists && validate.isEnabled { validate.tap() }
        }
        _ = require(app.tabBars.firstMatch, "tab bar after sign-in")
    }

    private func discoverSwipe() {
        openTab("Découvrir")
        let coach = button("J'ai compris")
        if coach.waitForExistence(timeout: 5) {
            snap("01-discover-swipe-coach")
            coach.tap()
        }
        let card = swipeTopCard
        _ = require(card, "top swipe card")
        snap("01-discover-swipe")
    }

    private func discoverGrid() {
        openTab("Découvrir")
        let grid = button("Grille")
        guard require(grid, "Grille segment") else { return }
        grid.tap()
        _ = require(element(prefix: "Robe wax imprimé"), "first grid card")
        snap("02-discover-grid")
    }

    private func filterSheet() {
        let filters = element(prefix: "Filtres")
        guard require(filters, "Filtres chip") else { return }
        filters.tap()
        let close = button("Fermer les filtres")
        guard require(close, "filter sheet") else { return }
        snap("03-filter-sheet")
        close.tap()
        _ = close.waitForNonExistence(timeout: timeout)
    }

    /// Back to Swipe, pass the Boubou (it already has a negotiation) so the next card — the leather bag,
    /// negotiable, no thread yet — shows "Faire une offre" on its product page.
    private func product() {
        openTab("Découvrir")
        let swipe = button("Swipe")
        if swipe.waitForExistence(timeout: timeout) { swipe.tap() }
        let card = swipeTopCard
        guard require(card, "top swipe card") else { return }
        if card.label.hasPrefix("Boubou") {
            let pass = button("Passer")
            if require(pass, "Passer button") {
                pass.tap()
                let next = NSPredicate(format: "label BEGINSWITH %@", "Sac à main")
                expectation(for: next, evaluatedWith: swipeTopCard)
                waitForExpectations(timeout: timeout) { error in
                    if error != nil { XCTFail("next swipe card is not the bag (got \(self.swipeTopCard.label))") }
                }
            }
        }
        swipeTopCard.tap()
        _ = require(app.navigationBars["Annonce"], "product page")
        _ = require(element(prefix: "Acheter pour"), "buy button")
        snap("04-product")
    }

    private func offerComposer() {
        let offer = button("Faire une offre")
        guard require(offer, "Faire une offre") else { return }
        offer.tap()
        _ = require(app.navigationBars["Faire une offre"], "offer composer")
        _ = require(element(prefix: "Envoyer l'offre"), "send offer button")
        snap("05-offer-composer")
        goBack()
    }

    private func checkout() {
        let buy = element(prefix: "Acheter pour")
        guard require(buy, "Acheter button") else { return }
        buy.tap()
        _ = require(app.navigationBars["Paiement"], "checkout")
        _ = require(element(prefix: "Payer avec"), "pay button")
        snap("06-checkout")
        openTab("Découvrir")   // re-selecting the tab pops to root
    }

    private func wishlist() {
        openTab("Envies")
        _ = require(app.navigationBars["Mes envies"], "wishlist")
        _ = require(element(prefix: "Boubou"), "wishlist item")
        snap("07-wishlist")
    }

    private func sell() {
        let sellTab = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vendre")).firstMatch
        guard require(sellTab, "Vendre tab") else { return }
        sellTab.tap()
        let close = button("Fermer")
        guard require(close, "sell flow") else { return }
        _ = require(element(prefix: "Continuer"), "sell flow primary button")
        snap("08-sell-step1")
        close.tap()
        if button("Abandonner l'annonce").waitForExistence(timeout: 2) { button("Abandonner l'annonce").tap() }
        _ = require(app.tabBars.firstMatch, "tab bar after closing the sell flow")
    }

    private func messages() {
        openTab("Messages")
        _ = require(app.navigationBars["Messages"], "messages list")
        _ = require(element(prefix: "SneakDak"), "conversation row")
        snap("09-messages")
    }

    private func chat() {
        let row = element(prefix: "SneakDak")
        guard require(row, "conversation row") else { return }
        row.tap()
        _ = require(element(containing: "Je peux t'envoyer une photo"), "chat messages")
        snap("10-chat")
        openTab("Messages")
    }

    private func profile() {
        openTab("Profil")
        _ = require(app.navigationBars["Profil"], "profile")
        _ = require(element(prefix: "Tableau de bord"), "dashboard entry")
        snap("11-profile")
    }

    private func dashboard() {
        let entry = element(prefix: "Tableau de bord")
        guard require(entry, "dashboard entry") else { return }
        entry.tap()
        _ = require(app.navigationBars["Tableau de bord"], "dashboard")
        snap("12-dashboard")
        openTab("Profil")
    }

    private func notifications() {
        let bell = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notifications")).firstMatch
        let fallback = element(prefix: "Notifications")
        if bell.waitForExistence(timeout: timeout) { bell.tap() }
        else if require(fallback, "notifications button") { fallback.tap() }
        _ = require(app.navigationBars["Notifications"], "notifications")
        _ = require(element(containing: "Contre-offre reçue"), "notification row")
        snap("13-notifications")
    }

    // MARK: - Helpers

    private var swipeTopCard: XCUIElement {
        app.descendants(matching: .any)["discover.swipe.topCard"]
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
    }

    /// Any element whose accessibility label starts with `prefix` (cards and rows combine their children).
    private func element(prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Selects a tab, then selects it again: re-selecting the current tab pops its stack to the root.
    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        guard require(tab, "tab \(name)") else { return }
        tab.tap()
        tab.tap()
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) { back.tap() }
    }

    /// Waits for an element; records a failure (and a screenshot of the unexpected state) if missing.
    @discardableResult
    private func require(_ element: XCUIElement, _ what: String,
                         file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        XCTFail("Missing: \(what)", file: file, line: line)
        snap("missing-\(what.replacingOccurrences(of: " ", with: "-"))")
        return false
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func step(_ name: String, _ body: () -> Void) {
        XCTContext.runActivity(named: name) { _ in body() }
    }
}
