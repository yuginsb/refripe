import XCTest
@testable import ReFripe

/// v3 transaction rules in the demo repository: guided payment, hand-off code, reviews, notifications,
/// moderation (report / block), photo messages and account deletion.
/// Seed: order 1 Awa → Fatou K. (AWAITING_SHIPMENT) · order 2 Awa → Karim (SHIPPED, code 4821) ·
/// order 3 Fatou → Awa (BUYER_VALIDATION) · orders 4 (SneakDak) and 5 (SecondLook) bought by Awa, COMPLETED.
final class V3TransactionTests: XCTestCase {

    // MARK: Guided payment

    func testStartPaymentWaveReturnsCheckoutAndFlipsToPaid() async throws {
        let repo = DemoRepository(paymentDelay: 0.3, shipDelay: nil)
        let o = try await repo.createOrder(listingId: DemoIDs.listing(6), delivery: .relais, payment: .wave)
        XCTAssertEqual(o.status, .paymentPending)
        XCTAssertNil(o.paymentReference)

        let session = try await repo.startPayment(orderId: o.id)
        XCTAssertEqual(session.orderId, o.id)
        XCTAssertEqual(session.method, .wave)
        XCTAssertEqual(session.amount, 6_500 + 1_000)
        XCTAssertEqual(session.checkoutURL, URL(string: "https://pay.wave.com/c/demo-\(o.id.uuidString.lowercased())"))
        XCTAssertNil(session.ussdCode)
        XCTAssertEqual(session.maskedPhone, "07 07 •• •• 07")
        let pending = try await repo.order(id: o.id)
        XCTAssertEqual(pending.status, .paymentPending, "paid only a few seconds after startPayment")

        let funded = await eventually { (try? await repo.order(id: o.id))?.status == .awaitingShipment }
        XCTAssertTrue(funded)
        let paid = try await repo.order(id: o.id)
        XCTAssertEqual(paid.history.map(\.status), [.paymentPending, .paid, .awaitingShipment])
        XCTAssertTrue(paid.paymentReference?.hasPrefix("WAVE-") ?? false, "receipt reference")

        await assertThrowsAsync(try await repo.startPayment(orderId: o.id)) {
            assertInvalidState($0, contains: "plus en attente de paiement")
        }
    }

    func testStartPaymentOrangeMoneyReturnsUSSD() async throws {
        let repo = DemoRepository(paymentDelay: 0.3, shipDelay: nil)
        let o = try await repo.createOrder(listingId: DemoIDs.listing(9), delivery: .relais, payment: .orangeMoney)
        let session = try await repo.startPayment(orderId: o.id)
        XCTAssertEqual(session.method, .orangeMoney)
        XCTAssertNil(session.checkoutURL)
        XCTAssertNotNil(session.ussdCode)
        let funded = await eventually { (try? await repo.order(id: o.id))?.status == .awaitingShipment }
        XCTAssertTrue(funded)
        let paid = try await repo.order(id: o.id)
        XCTAssertTrue(paid.paymentReference?.hasPrefix("OM-") ?? false)
    }

    func testNoPaymentWithoutStartPayment() async throws {
        let repo = DemoRepository(paymentDelay: 0.2, shipDelay: nil)
        let o = try await repo.createOrder(listingId: DemoIDs.listing(6), delivery: .relais, payment: .wave)
        try await Task.sleep(nanoseconds: 800_000_000)
        let still = try await repo.order(id: o.id)
        XCTAssertEqual(still.status, .paymentPending)
    }

    func testOnlyTheBuyerCanStartPayment() async throws {
        let state = makeDemoState()
        try await signIn(state, phone: TestPhones.karim)
        let o = try await state.createOrder(listingId: DemoIDs.listing(5), delivery: .relais, payment: .wave)
        try await signIn(state, phone: DemoIDs.awaPhone)
        await assertThrowsAsync(try await state.startPayment(orderId: o.id)) { assertNotFound($0) }
    }

    func testMaskedPhone() {
        XCTAssertEqual(DemoState.maskedPhone("0707070707"), "07 07 •• •• 07")
        XCTAssertEqual(DemoState.maskedPhone("+225 01 02 03 04 05"), "01 02 •• •• 05")
        XCTAssertNil(DemoState.maskedPhone("1234"))
    }

    func testPaidOrderNotifiesSellerWithNewSale() async throws {
        let state = makeDemoState()
        try await signIn(state, phone: TestPhones.karim)
        let o = try await state.createOrder(listingId: DemoIDs.listing(5), delivery: .relais, payment: .wave)
        _ = try await state.startPayment(orderId: o.id)
        let funded = await eventually { (try? await state.order(id: o.id))?.status == .awaitingShipment }
        XCTAssertTrue(funded)
        try await signIn(state, phone: DemoIDs.awaPhone)
        let notifs = try await state.notifications()
        XCTAssertTrue(notifs.contains { $0.kind == .newSale && $0.orderId == o.id })
    }

    func testSimulatedSellerShipsMyPurchaseAndOnlyIShowTheCode() async throws {
        let repo = DemoRepository(paymentDelay: 0.1, shipDelay: 0.3)
        let o = try await repo.createOrder(listingId: DemoIDs.listing(6), delivery: .yango, payment: .wave)
        _ = try await repo.startPayment(orderId: o.id)
        let shipped = await eventually { (try? await repo.order(id: o.id))?.status == .shipped }
        XCTAssertTrue(shipped)
        let mine = try await repo.order(id: o.id)
        XCTAssertEqual(mine.handoffCode?.count, 4)
        XCTAssertTrue(mine.handoffCode?.allSatisfy(\.isNumber) ?? false)
    }

    // MARK: Hand-off code

    func testHandoffCodeIsVisibleOnlyToTheBuyer() async throws {
        let state = makeDemoState()
        // Awa sells order 2: no code, anywhere.
        let asSeller = try await state.order(id: DemoIDs.order(2))
        XCTAssertNil(asSeller.handoffCode)
        let selling = try await state.orders(role: .seller)
        XCTAssertTrue(selling.allSatisfy { $0.handoffCode == nil })
        // Awa bought order 3: she sees her own code.
        let asBuyer = try await state.order(id: DemoIDs.order(3))
        XCTAssertEqual(asBuyer.handoffCode, DemoIDs.order3HandoffCode)

        try await signIn(state, phone: TestPhones.karim)
        let karims = try await state.order(id: DemoIDs.order(2))
        XCTAssertEqual(karims.handoffCode, DemoIDs.order2HandoffCode)
        let buying = try await state.orders(role: .buyer)
        XCTAssertEqual(buying.first { $0.id == DemoIDs.order(2) }?.handoffCode, DemoIDs.order2HandoffCode)
    }

    func testCodeIsGeneratedWhenShipped() async throws {
        let state = makeDemoState()
        let before = try await state.order(id: DemoIDs.order(1))
        XCTAssertNil(before.handoffCode)
        _ = try await state.advanceOrder(id: DemoIDs.order(1), to: .shipped)
        try await signIn(state, phone: TestPhones.fatouK)
        let after = try await state.order(id: DemoIDs.order(1))
        XCTAssertEqual(after.handoffCode?.count, 4)
        // Only the seller ships.
        let fresh = makeDemoState()
        try await signIn(fresh, phone: TestPhones.fatouK)
        await assertThrowsAsync(try await fresh.advanceOrder(id: DemoIDs.order(1), to: .shipped)) {
            assertInvalidState($0, contains: "Seule la vendeuse")
        }
    }

    func testConfirmHandoffValidatesTheCode() async throws {
        let clock = TestClock()
        let state = makeDemoState(clock: clock)
        await assertThrowsAsync(try await state.confirmHandoff(orderId: DemoIDs.order(2), code: "0000")) {
            assertInvalidState($0, contains: "Code incorrect")
        }
        let still = try await state.order(id: DemoIDs.order(2))
        XCTAssertEqual(still.status, .shipped)

        let o = try await state.confirmHandoff(orderId: DemoIDs.order(2), code: " 48 21 ")
        XCTAssertEqual(o.status, .buyerValidation)
        XCTAssertEqual(o.history.suffix(3).map(\.status), [.shipped, .delivered, .buyerValidation])
        XCTAssertEqual(o.escrowReleaseAt, clock.now.addingTimeInterval(72 * 3_600))
        XCTAssertNil(o.handoffCode, "still hidden from the seller")

        let notifsState = state
        try await signIn(notifsState, phone: TestPhones.karim)
        let notifs = try await notifsState.notifications()
        XCTAssertTrue(notifs.contains { $0.orderId == DemoIDs.order(2) && $0.title == "Confirme la réception" })
    }

    func testConfirmHandoffRules() async throws {
        let state = makeDemoState()
        // Not shipped yet.
        await assertThrowsAsync(try await state.confirmHandoff(orderId: DemoIDs.order(1), code: "1234")) {
            assertInvalidState($0, contains: "n'attend pas de remise")
        }
        // The buyer gives the code, she doesn't type it.
        try await signIn(state, phone: TestPhones.karim)
        await assertThrowsAsync(try await state.confirmHandoff(orderId: DemoIDs.order(2), code: DemoIDs.order2HandoffCode)) {
            assertInvalidState($0, contains: "Le code se donne")
        }
        // Strangers don't see the order.
        try await signIn(state, phone: TestPhones.sneak)
        await assertThrowsAsync(try await state.confirmHandoff(orderId: DemoIDs.order(2), code: DemoIDs.order2HandoffCode)) {
            assertNotFound($0)
        }
    }

    func testSeedEscrowDeadline() async throws {
        let repo = DemoRepository()
        let o3 = try await repo.order(id: DemoIDs.order(3))
        let delivered = o3.history.first { $0.status == .delivered }?.at
        XCTAssertNotNil(delivered)
        XCTAssertEqual(o3.escrowReleaseAt, delivered?.addingTimeInterval(72 * 3_600))
        XCTAssertNotNil(o3.paymentReference)
    }

    // MARK: Reviews

    func testSeededReviewsMatchAwasRating() async throws {
        let repo = DemoRepository()
        let reviews = try await repo.reviews(userId: DemoIDs.awa)
        let awa = try await repo.profile(id: DemoIDs.awa)
        XCTAssertEqual(reviews.count, awa.reviewCount)
        XCTAssertEqual(awa.reviewCount, 10)
        let average = Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count)
        XCTAssertEqual(average, awa.rating, accuracy: 0.001)
        XCTAssertEqual(reviews.map(\.createdAt), reviews.map(\.createdAt).sorted(by: >), "newest first")
    }

    func testSubmitReviewUpdatesRatingAndCountOncePerOrder() async throws {
        let repo = DemoRepository()
        let before = try await repo.profile(id: DemoIDs.sneak)          // 4.9 ★, 86 reviews
        let review = try await repo.submitReview(orderId: DemoIDs.order(4), rating: 3, comment: "  Bien, un peu usé  ")
        XCTAssertEqual(review.revieweeId, DemoIDs.sneak)
        XCTAssertEqual(review.reviewerId, DemoIDs.awa)
        XCTAssertEqual(review.comment, "Bien, un peu usé")

        let after = try await repo.profile(id: DemoIDs.sneak)
        XCTAssertEqual(after.reviewCount, before.reviewCount + 1)
        let expected = (before.rating * Double(before.reviewCount) + 3) / Double(before.reviewCount + 1)
        XCTAssertEqual(after.rating, expected, accuracy: 0.0001)
        XCTAssertLessThan(after.rating, before.rating)
        let listed = try await repo.reviews(userId: DemoIDs.sneak)
        XCTAssertEqual(listed.first?.id, review.id)

        await assertThrowsAsync(try await repo.submitReview(orderId: DemoIDs.order(4), rating: 5, comment: "")) {
            assertInvalidState($0, contains: "déjà noté")
        }
    }

    func testReviewRules() async throws {
        let state = makeDemoState()
        // Not completed yet.
        await assertThrowsAsync(try await state.submitReview(orderId: DemoIDs.order(3), rating: 5, comment: "")) {
            assertInvalidState($0, contains: "une fois la commande terminée")
        }
        await assertThrowsAsync(try await state.submitReview(orderId: DemoIDs.order(5), rating: 0, comment: "")) {
            assertInvalidState($0, contains: "1 à 5")
        }
        await assertThrowsAsync(try await state.submitReview(orderId: DemoIDs.order(5), rating: 6, comment: "")) {
            assertInvalidState($0, contains: "1 à 5")
        }
        // Only the buyer reviews: Karim completes order 2, then Awa (seller) tries.
        try await signIn(state, phone: TestPhones.karim)
        _ = try await state.advanceOrder(id: DemoIDs.order(2), to: .delivered)
        _ = try await state.advanceOrder(id: DemoIDs.order(2), to: .completed)
        try await signIn(state, phone: DemoIDs.awaPhone)
        await assertThrowsAsync(try await state.submitReview(orderId: DemoIDs.order(2), rating: 5, comment: "")) {
            assertInvalidState($0, contains: "Seule l'acheteuse")
        }
        try await signIn(state, phone: TestPhones.karim)
        let ok = try await state.submitReview(orderId: DemoIDs.order(2), rating: 5, comment: "Parfait")
        XCTAssertEqual(ok.revieweeId, DemoIDs.awa)
        let awa = try await state.profile(id: DemoIDs.awa)
        XCTAssertEqual(awa.reviewCount, 11)
    }

    // MARK: Offer notifications

    func testNewBuyerOfferNotifiesTheSeller() async throws {
        let state = makeDemoState()
        try await signIn(state, phone: TestPhones.karim)
        _ = try await state.makeOffer(listingId: DemoIDs.listing(1), amount: 3_800)
        try await signIn(state, phone: DemoIDs.awaPhone)
        let notifs = try await state.notifications()
        XCTAssertTrue(notifs.contains { $0.kind == .offerReceived && $0.listingId == DemoIDs.listing(1) })
    }

    func testSellerAnswerNotifiesTheBuyer() async throws {
        let state = makeDemoState()
        _ = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .refuse, amount: nil)
        try await signIn(state, phone: TestPhones.karim)
        let notifs = try await state.notifications()
        XCTAssertTrue(notifs.contains { $0.kind == .offerRefused && $0.listingId == DemoIDs.listing(7) })
    }

    // MARK: Moderation

    func testBlockHidesListingsConversationsAndPurchases() async throws {
        let repo = DemoRepository()
        try await repo.block(userId: DemoIDs.sneak)
        let blocked = try await repo.blockedUserIds()
        XCTAssertEqual(blocked, [DemoIDs.sneak])

        let feed = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertFalse(feed.contains { $0.sellerId == DemoIDs.sneak })
        let deck = try await repo.swipeDeck(preferences: nil)
        XCTAssertFalse(deck.contains { $0.sellerId == DemoIDs.sneak })
        let convs = try await repo.conversations()
        XCTAssertFalse(convs.contains { $0.otherUserId == DemoIDs.sneak })
        await assertThrowsAsync(try await repo.send(text: "Toujours dispo ?", conversationId: DemoIDs.conversationBaskets)) {
            assertInvalidState($0, contains: "plus échanger")
        }
        await assertThrowsAsync(try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "ce membre")
        }

        try await repo.unblock(userId: DemoIDs.sneak)
        let unblocked = try await repo.blockedUserIds()
        XCTAssertTrue(unblocked.isEmpty)
        let back = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertTrue(back.contains { $0.id == DemoIDs.listing(3) })
    }

    func testBlockedMemberDoesNotSeeMyListingsEither() async throws {
        let state = makeDemoState()
        try await state.block(userId: DemoIDs.karim)
        try await signIn(state, phone: TestPhones.karim)
        let feed = await state.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertFalse(feed.contains { $0.sellerId == DemoIDs.awa })
    }

    func testCannotBlockOrReportYourself() async throws {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.block(userId: DemoIDs.awa)) { assertInvalidState($0, contains: "toi-même") }
        await assertThrowsAsync(try await repo.report(listingId: nil, userId: DemoIDs.awa, reason: .scam, details: "")) {
            assertInvalidState($0, contains: "toi-même")
        }
        await assertThrowsAsync(try await repo.report(listingId: nil, userId: nil, reason: .other, details: "")) {
            assertInvalidState($0, contains: "signaler")
        }
    }

    func testReportIsStored() async throws {
        let state = makeDemoState()
        try await state.report(listingId: DemoIDs.listing(3), userId: nil, reason: .counterfeit, details: " Logo douteux ")
        try await state.report(listingId: nil, userId: DemoIDs.karim, reason: .scam, details: "Demande un paiement hors app")
        let reports = await state.reports
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first?.reason, .counterfeit)
        XCTAssertEqual(reports.first?.details, "Logo douteux")
        XCTAssertEqual(reports.last?.userId, DemoIDs.karim)
    }

    // MARK: Photo messages

    func testSendPhotoStoresADisplayableFile() async throws {
        let repo = DemoRepository()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let msg = try await repo.sendPhoto(jpeg, conversationId: DemoIDs.conversationRobeWax)
        XCTAssertEqual(msg.senderId, DemoIDs.awa)
        XCTAssertEqual(msg.text, "")
        let url = try XCTUnwrap(msg.photo?.url)
        XCTAssertTrue(url.isFileURL, "ListingPhotoView loads file URLs directly")
        XCTAssertEqual(try Data(contentsOf: url), jpeg)

        let convs = try await repo.conversations()
        XCTAssertEqual(convs.first { $0.id == DemoIDs.conversationRobeWax }?.lastMessage, "Photo")
        let messages = try await repo.messages(conversationId: DemoIDs.conversationRobeWax)
        XCTAssertEqual(messages.last?.id, msg.id)
        await assertThrowsAsync(try await repo.sendPhoto(Data(), conversationId: DemoIDs.conversationRobeWax)) {
            assertInvalidState($0, contains: "Photo vide")
        }
    }

    // MARK: Account deletion

    func testDeleteAccountSignsOutAndRemovesMyData() async throws {
        let state = makeDemoState()
        try await state.deleteAccount()
        let me = await state.me
        XCTAssertNil(me)
        let restored = await state.restoreSession()
        XCTAssertNil(restored)
        let listings = await state.listings(sellerId: DemoIDs.awa)
        XCTAssertTrue(listings.isEmpty)
        await assertThrowsAsync(try await state.profile(id: DemoIDs.awa)) { assertNotFound($0) }
        // The phone number now starts a fresh signup.
        let again = try await state.verifyOTP(phone: DemoIDs.awaPhone, code: DemoIDs.otpCode)
        XCTAssertNil(again)
        // Past orders are kept, anonymised.
        try await signIn(state, phone: TestPhones.sneak)
        let sold = try await state.orders(role: .seller)
        XCTAssertEqual(sold.first { $0.id == DemoIDs.order(4) }?.buyerName, "Compte supprimé")
        let feed = await state.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertFalse(feed.contains { $0.sellerId == DemoIDs.awa })
    }

    func testDeleteAccountRequiresASession() async throws {
        let repo = DemoRepository()
        try await repo.signOut()
        await assertThrowsAsync(try await repo.deleteAccount()) {
            guard case RepositoryError.notAuthenticated = $0 else { return XCTFail("expected notAuthenticated, got \($0)") }
        }
    }
}
