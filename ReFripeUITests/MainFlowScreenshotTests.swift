import XCTest

/// Walks the main v3 flow of the demo app and attaches a screenshot of every screen
/// (`XCTAttachment`, kept always). CI exports them from the .xcresult to the `ci-screens` branch.
///
/// Launch arguments:
/// - `-uiTestingSignedOut`: the demo starts signed out so the sign-up flow is shown; the test signs back in
///   as Awa (demo phone 07 07 07 07 07, code 1234).
/// - `-uiTestingSellPhoto`: « Vendre » starts from an empty form with one bundled photo (no photo picker in tests).
///
/// A missing element records a failure but the walk goes on (`continueAfterFailure = true`).
/// Queries use identifiers on the Profil / Réglages / Vendre screens and the visible labels named in
/// docs/DESIGN-v3.md elsewhere (« Faire une offre », « Acheter », « Payer avec Wave », « Ouvrir Wave »…).
@MainActor
final class MainFlowScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let timeout: TimeInterval = 15

    func testMainFlowScreenshots() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-uiTestingSignedOut", "-uiTestingSellPhoto"]
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
        step("01 accueil grid") { homeGrid() }
        step("02 filter sheet") { filterSheet() }
        step("03 coup de coeur") { coupDeCoeur() }
        step("04 product") { product() }
        step("05 chat offer") { chatOffer() }
        step("06 checkout + payment") { checkoutAndPayment() }
        step("07 messages") { messages() }
        step("08 favoris") { favoris() }
        step("09 sell") { sell() }
        step("10 profile") { profile() }
        step("11 purchases") { purchases() }
        step("12 reviews") { reviews() }
        step("13 stats") { stats() }
        step("14 settings") { settings() }
    }

    /// Same app in dark mode (`-appearanceMode dark` sets the Réglages › Apparence value): a few key screens.
    func testDarkModeScreenshots() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-uiTestingSignedOut", "-appearanceMode", "dark"]
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Autoriser", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()
        if button("Continuer avec mon numéro").waitForExistence(timeout: timeout) { snap("20-dark-signup") }
        signUp()
        openTab("Accueil")
        _ = require(element(prefix: "Filtres"), "dark Accueil")
        snap("21-dark-accueil")
        let card = element(prefix: "Chemise vintage")
        if require(card, "dark grid card") {
            tapScrolling(card)
            if require(productBuy, "dark product page") { snap("22-dark-product") }
        }
        openTab("Messages")
        _ = require(app.navigationBars["Messages"], "dark Messages")
        snap("23-dark-messages")
        openTab("Profil")
        _ = require(app.navigationBars["Profil"], "dark Profil")
        snap("24-dark-profile")
    }

    // MARK: - Sign-up

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
        // The real code field is a 1-pt hidden field under the digit boxes; tapping the boxes focuses it.
        let code = app.textFields["Code de vérification à 4 chiffres"]
        guard require(code, "code field") else { return }
        code.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        code.typeText("1234")   // 4 digits → verifies automatically

        // Signed back in as Awa (onboarding already completed) → the cover closes on the tab bar.
        if !app.tabBars.firstMatch.waitForExistence(timeout: timeout) {
            let validate = button("Valider")
            if validate.exists && validate.isEnabled { validate.tap() }
        }
        _ = require(app.tabBars.firstMatch, "tab bar after sign-in")
    }

    // MARK: - Accueil

    /// Default screen: grid with the quick chips (Filtres · Ma taille · Moins de 5 000 · Près de moi).
    private func homeGrid() {
        openTab("Accueil")
        _ = require(app.navigationBars["Accueil"], "Accueil")
        _ = require(element(prefix: "Filtres"), "Filtres chip")
        _ = require(element(prefix: "Chemise vintage"), "grid card")
        // Regression: my own listings are excluded from the feed.
        // (The feed reloads once the sign-in lands: give it a moment.)
        XCTAssertTrue(element(prefix: "Robe wax imprimé").waitForNonExistence(timeout: 5), "own listing in the Accueil feed")
        snap("01-accueil-grid")
    }

    private func filterSheet() {
        let filters = element(prefix: "Filtres")
        guard require(filters, "Filtres chip") else { return }
        filters.tap()
        let close = button("Fermer les filtres")
        guard require(close, "filter sheet") else { return }
        snap("02-filter-sheet")
        close.tap()
        _ = close.waitForNonExistence(timeout: timeout)
    }

    private func coupDeCoeur() {
        let card = app.descendants(matching: .any)["home.coupDeCoeur"]
        guard require(card, "Coup de cœur card") else { return }
        tapScrolling(card)
        let coach = button("Compris")
        if coach.waitForExistence(timeout: 5) {
            snap("03-coup-de-coeur-coach")
            coach.tap()
        }
        _ = require(swipeTopCard, "top swipe card")
        snap("03-coup-de-coeur")
        openTab("Accueil")
    }

    /// The leather bag is negotiable and has no negotiation yet: its page shows « Faire une offre ».
    private func product() {
        openTab("Accueil")
        let card = element(prefix: "Sac à main")
        guard require(card, "leather bag card") else { return }
        tapScrolling(card)
        // The product page hides its navigation bar (photo goes edge to edge): check its action bar instead.
        _ = require(productBuy, "product page")
        _ = require(productBuy, "Acheter button")
        _ = require(productOffer, "Faire une offre button")
        snap("04-product")
    }

    // MARK: - Chat + offer bubbles

    /// « Faire une offre » opens the conversation; the offer is sent from the chat (quick reply), then the
    /// demo seller answers (~1,5 s) with a counter-offer bubble (Accepter / Proposer).
    private func chatOffer() {
        guard require(productOffer, "Faire une offre button") else { return }
        productOffer.tap()
        // Wait for the product page to go away (its own « Faire une offre » button has the same label).
        _ = productOffer.waitForNonExistence(timeout: timeout)
        let quickOffer = button("Faire une offre")
        guard require(quickOffer, "chat quick reply Faire une offre") else { return }
        snap("05-chat")
        quickOffer.tap()
        let sendOffer = element(prefix: "Envoyer l'offre")
        guard require(sendOffer, "offer composer") else { return }
        snap("05-chat-offer-composer")
        sendOffer.tap()
        _ = sendOffer.waitForNonExistence(timeout: timeout)
        snap("05-chat-offer-sent")
        // Counter-offer (or acceptance) from the demo seller.
        let answer = element(prefix: "Accepter")
        if answer.waitForExistence(timeout: 8) {
            snap("05-chat-offer-answer")
        } else {
            XCTFail("no answer bubble from the demo seller")
            snap("missing-offer-answer")
        }
        goBack()   // back to the product page
    }

    // MARK: - Checkout → payment pending → receipt → tracking

    private func checkoutAndPayment() {
        guard require(productBuy, "Acheter button") else { return }
        productBuy.tap()
        _ = require(app.navigationBars["Paiement"], "checkout")
        let pay = element(prefix: "Payer avec Wave")
        guard require(pay, "Payer avec Wave") else { return }
        snap("06-checkout")
        pay.tap()

        // « Confirme dans Wave » screen (do not tap « Ouvrir Wave »: it would leave the app).
        if require(element(prefix: "Ouvrir Wave"), "payment pending") {
            snap("06-payment-pending")
        }
        // Demo: PAID ~4 s after startPayment → receipt.
        let track = element(prefix: "Suivre ma commande")
        if track.waitForExistence(timeout: 20) {
            snap("06-payment-receipt")
            track.tap()
            _ = require(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Commande")).firstMatch,
                        "order tracking")
            snap("06-order-tracking")
        } else {
            if app.state != .runningForeground { app.activate() }
            XCTFail("payment receipt not shown")
            snap("missing-payment-receipt")
        }
        openTab("Accueil")
    }

    // MARK: - Messages, Favoris

    private func messages() {
        openTab("Messages")
        _ = require(app.navigationBars["Messages"], "Messages")
        _ = require(element(containing: "À faire"), "À faire section")
        _ = require(element(prefix: "SneakDak"), "conversation row")
        snap("07-messages")
    }

    private func favoris() {
        openTab("Favoris")
        _ = require(app.navigationBars["Favoris"], "Favoris")
        _ = require(element(prefix: "Boubou"), "favorite item")
        snap("08-favoris")
    }

    // MARK: - Vendre (4 steps)

    private func sell() {
        let sellTab = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vendre")).firstMatch
        guard require(sellTab, "Vendre tab") else { return }
        sellTab.tap()
        let primary = app.buttons["sell.primary"]
        guard require(primary, "sell flow") else { return }

        // 1 · Photos (demo photo injected by -uiTestingSellPhoto, checked on-device — slow on CI simulators).
        waitUntilEnabled(primary, timeout: 45)
        snap("09-sell-1-photos")
        primary.tap()

        // 2 · L'article
        if require(id("sell.itemType.robe"), "item type chips") {
            tapScrolling(id("sell.itemType.robe"))
            let femme = app.segmentedControls.buttons["Femme"].firstMatch
            if require(femme, "Pour segment") { femme.tap() }
            let size = id("sell.size.M")
            if require(size, "size chips") { tapScrolling(size) }
            let condition = id("sell.condition.very_good")
            if require(condition, "condition rows") { tapScrolling(condition) }
            app.swipeDown()   // back to the top for the capture
            snap("09-sell-2-article")
            waitUntilEnabled(primary)
            primary.tap()
        }

        // 3 · Ton prix
        let price = app.textFields["sell.price"]
        if require(price, "price field") {
            price.tap()
            price.typeText("4500")
            snap("09-sell-3-prix")
            waitUntilEnabled(primary)
            primary.tap()
        }

        // 4 · Remise + relecture
        if require(id("sell.delivery.relais"), "delivery rows") {
            snap("09-sell-4-remise")
        }

        // Closing keeps the draft (« Brouillon enregistré »), no confirmation.
        let close = button("Fermer")
        if require(close, "close button") { close.tap() }
        _ = require(app.tabBars.firstMatch, "tab bar after closing the sell flow")
    }

    // MARK: - Profil

    private func profile() {
        openTab("Profil")
        _ = require(app.navigationBars["Profil"], "profile")
        _ = require(element(containing: "Mon dressing"), "dressing")
        snap("10-profile")
        let activity = id("profile.activity.purchases")
        if require(activity, "Mon activité") {
            scrollUntilHittable(id("profile.activity.help"))
            snap("10-profile-activity")
        }
    }

    private func purchases() {
        let row = id("profile.activity.purchases")
        guard require(row, "Mes achats row") else { return }
        tapScrolling(row)
        _ = require(app.navigationBars["Mes achats"], "Mes achats")
        snap("11-mes-achats")
        goBack()
        let sales = id("profile.activity.sales")
        if require(sales, "Mes ventes row") {
            tapScrolling(sales)
            _ = require(app.navigationBars["Mes ventes"], "Mes ventes")
            snap("11-mes-ventes")
            goBack()
        }
        let payouts = id("profile.activity.payouts")
        if require(payouts, "Versements row") {
            tapScrolling(payouts)
            _ = require(app.navigationBars["Versements"], "Versements")
            snap("11-versements")
            goBack()
        }
    }

    private func reviews() {
        openTab("Profil")
        let rating = id("profile.reviews")
        guard require(rating, "rating button") else { return }
        tapScrolling(rating)
        _ = require(app.navigationBars["Avis"], "reviews")
        snap("12-avis")
        openTab("Profil")
    }

    private func stats() {
        openTab("Profil")
        let entry = id("profile.activity.stats")
        guard require(entry, "Statistiques row") else { return }
        tapScrolling(entry)
        _ = require(app.navigationBars["Statistiques"], "stats")
        snap("13-stats")
        openTab("Profil")
    }

    private func settings() {
        openTab("Profil")
        let gear = app.navigationBars.buttons["Réglages"].firstMatch
        guard require(gear, "settings button") else { return }
        gear.tap()
        _ = require(app.navigationBars["Réglages"], "settings")
        _ = require(element(prefix: "Pseudo"), "account section")
        snap("14-settings")
        let delete = id("settings.deleteAccount")
        // The Form is lazy: the last rows only exist once scrolled into view.
        var swipes = 0
        while !delete.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        if require(delete, "Supprimer mon compte") {
            scrollUntilHittable(delete)
            snap("14-settings-bottom")
        }
        openTab("Profil")
    }

    // MARK: - Helpers

    private var swipeTopCard: XCUIElement {
        app.descendants(matching: .any)["discover.swipe.topCard"]
    }

    private var productOffer: XCUIElement { app.buttons["product.offer"].firstMatch }
    private var productBuy: XCUIElement { app.buttons["product.buy"].firstMatch }

    private func button(_ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
    }

    private func id(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
        // Pushed screens (order tracking, product…) hide the tab bar: pop back to the tab root first.
        var pops = 0
        while !app.tabBars.firstMatch.waitForExistence(timeout: 2) && pops < 5 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            let custom = app.buttons["Retour"].firstMatch
            if back.exists && back.isHittable { back.tap() }
            else if custom.exists && custom.isHittable { custom.tap() }
            else {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
            }
            pops += 1
        }
        let tab = app.tabBars.buttons[name]
        guard require(tab, "tab \(name)") else { return }
        tab.tap()
        tab.tap()
    }

    /// Scrolls the current screen up (a few times at most) until the element can be tapped.
    private func scrollUntilHittable(_ element: XCUIElement) {
        var tries = 0
        while element.exists && !element.isHittable && tries < 5 {
            app.swipeUp()
            tries += 1
        }
    }

    private func tapScrolling(_ element: XCUIElement) {
        scrollUntilHittable(element)
        element.tap()
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 15) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        if XCTWaiter.wait(for: [enabled], timeout: timeout) != .completed {
            XCTFail("\(element.identifier) stayed disabled")
            snap("disabled-\(element.identifier)")
        }
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
