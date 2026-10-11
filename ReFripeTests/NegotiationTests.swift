import XCTest
@testable import ReFripe

/// Negotiation through the demo repository (same rules as the Supabase `make_offer` / `respond_offer` RPCs).
/// Signed-in user in demo mode: Awa (seller of listings 1, 5, 7).
final class NegotiationTests: XCTestCase {

    private let karimPhone = "0101010101"

    /// Demo state with extra offer threads and a phone number that signs in as Karim.
    private func makeState(threads extra: [OfferThread] = []) -> DemoState {
        var seed = DemoSeed.make()
        seed.threads += extra
        seed.phones[karimPhone] = DemoIDs.karim
        return DemoState(seed: seed)
    }

    private func round(_ by: OfferParty, _ amount: FCFA, _ action: OfferAction) -> OfferRound {
        OfferRound(by: by, amount: amount, action: action, at: .now.addingTimeInterval(-60))
    }

    // MARK: Amount validation

    func testOfferMustBeBelowListedPrice() async {
        let repo = DemoRepository()
        let baskets = DemoIDs.listing(3)   // 8 000 FCFA
        await assertThrowsAsync(try await repo.makeOffer(listingId: baskets, amount: 8_000)) {
            assertInvalidState($0, contains: "inférieure au prix affiché")
        }
        await assertThrowsAsync(try await repo.makeOffer(listingId: baskets, amount: 9_500)) {
            assertInvalidState($0, contains: "inférieure au prix affiché")
        }
    }

    func testOfferMustBePositive() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 0)) {
            assertInvalidState($0, contains: "Indique un montant")
        }
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: -500)) {
            assertInvalidState($0, contains: "Indique un montant")
        }
        let thread = try? await repo.offerThread(listingId: DemoIDs.listing(3))
        XCTAssertNil(thread, "a rejected offer must not create a thread")
    }

    func testNoOfferOnOwnOrFixedPriceListing() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(1), amount: 3_000)) {
            assertInvalidState($0, contains: "ton propre article")
        }
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(2), amount: 1_500)) {
            assertInvalidState($0, contains: "n'accepte pas les offres")
        }
    }

    // MARK: Thread lifecycle

    func testFirstOfferOpensPendingThreadAndBlocksUntilSellerAnswers() async throws {
        let repo = DemoRepository()
        let t = try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 6_000)
        XCTAssertEqual(t.status, .pending)
        XCTAssertEqual(t.buyerOfferCount, 1)
        XCTAssertEqual(t.lastBuyerOffer?.amount, 6_000)
        XCTAssertEqual(t.sellerId, DemoIDs.sneak)
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 6_500)) {
            assertInvalidState($0, contains: "Attends la réponse")
        }
    }

    func testOfferMeetingSellerCounterAcceptsItAtCounterAmount() async throws {
        let repo = DemoRepository()
        // Seed: Boubou (10 000) — Awa offered 7 000, Fatou countered 8 500.
        let t = try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 9_000)
        XCTAssertEqual(t.status, .accepted)
        XCTAssertEqual(t.acceptedAmount, 8_500, "meeting the counter accepts the counter, not the higher amount")
        XCTAssertEqual(t.rounds.last?.by, .buyer)
        XCTAssertEqual(t.rounds.last?.action, .accept)
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 9_500)) {
            assertInvalidState($0, contains: "déjà été acceptée")
        }
    }

    func testOfferExactlyAtCounterAccepts() async throws {
        let repo = DemoRepository()
        let t = try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 8_500)
        XCTAssertEqual(t.status, .accepted)
        XCTAssertEqual(t.acceptedAmount, 8_500)
    }

    func testOfferBelowCounterStaysPending() async throws {
        let repo = DemoRepository()
        let t = try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 8_000)
        XCTAssertEqual(t.status, .pending)
        XCTAssertEqual(t.buyerOfferCount, 2)
        XCTAssertEqual(t.lastBuyerOffer?.amount, 8_000)
        XCTAssertNil(t.acceptedAmount)
    }

    /// Bug fixed in DemoRepository: the RPC rejects an offer that doesn't beat the previous one; the demo didn't.
    func testNewOfferMustBeatPreviousOffer() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 7_000)) {
            assertInvalidState($0, contains: "dépasser la précédente")
        }
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 6_500)) {
            assertInvalidState($0, contains: "dépasser la précédente")
        }
    }

    func testAtMostThreeBuyerOffers() async {
        let listing = DemoIDs.listing(3)
        let thread = OfferThread(id: UUID(), listingId: listing, buyerId: DemoIDs.awa, sellerId: DemoIDs.sneak,
                                 rounds: [round(.buyer, 5_000, .offer), round(.seller, 7_500, .counter),
                                          round(.buyer, 5_500, .offer), round(.seller, 7_000, .counter),
                                          round(.buyer, 6_000, .offer), round(.seller, 6_500, .counter)],
                                 status: .pending, updatedAt: .now)
        XCTAssertEqual(thread.buyerOfferCount, 3)
        let state = makeState(threads: [thread])
        await assertThrowsAsync(try await state.makeOffer(listingId: listing, amount: 6_200)) {
            assertOfferLimitReached($0)
        }
        // Same order of checks as the RPC: the limit applies before the counter-acceptance shortcut.
        await assertThrowsAsync(try await state.makeOffer(listingId: listing, amount: 6_500)) {
            assertOfferLimitReached($0)
        }
    }

    // MARK: Seller bot (demo)

    func testSellerBotAcceptsHighOfferAndOrderUsesAcceptedPrice() async throws {
        let repo = DemoRepository()
        _ = try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 7_000)
        let accepted = await eventually {
            (try? await repo.offerThread(listingId: DemoIDs.listing(3)))?.status == .accepted
        }
        XCTAssertTrue(accepted, "the demo seller should accept an offer at 90 % of the price")
        let thread = try await repo.offerThread(listingId: DemoIDs.listing(3))
        XCTAssertEqual(thread?.acceptedAmount, 7_000)

        let order = try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)
        XCTAssertEqual(order.itemPrice, 7_000)
        XCTAssertEqual(order.deliveryFee, 1_000)
        XCTAssertEqual(order.total, 8_000)
    }

    func testSellerBotCountersLowFirstOffer() async throws {
        let repo = DemoRepository()
        _ = try await repo.makeOffer(listingId: DemoIDs.listing(6), amount: 4_000)
        let countered = await eventually {
            (try? await repo.offerThread(listingId: DemoIDs.listing(6)))?.lastSellerCounter != nil
        }
        XCTAssertTrue(countered)
        let thread = try await repo.offerThread(listingId: DemoIDs.listing(6))
        XCTAssertEqual(thread?.status, .pending)
        XCTAssertEqual(thread?.lastSellerCounter?.amount, 5_500)
        let notifs = try await repo.notifications()
        XCTAssertTrue(notifs.contains { $0.title == "Contre-offre reçue" && $0.listingId == DemoIDs.listing(6) })
    }

    func testSellerBotRefusalAfterThirdLowOfferClosesThread() async throws {
        let listing = DemoIDs.listing(3)   // floor 6 000
        let thread = OfferThread(id: UUID(), listingId: listing, buyerId: DemoIDs.awa, sellerId: DemoIDs.sneak,
                                 rounds: [round(.buyer, 1_000, .offer), round(.seller, 4_500, .counter),
                                          round(.buyer, 1_500, .offer), round(.seller, 5_000, .counter)],
                                 status: .pending, updatedAt: .now)
        let state = makeState(threads: [thread])
        let third = try await state.makeOffer(listingId: listing, amount: 2_000)
        XCTAssertEqual(third.buyerOfferCount, 3)
        let refused = await eventually { (try? await state.offerThread(listingId: listing))?.status == .refused }
        XCTAssertTrue(refused, "3rd offer under the floor must be refused by the demo seller")
        await assertThrowsAsync(try await state.makeOffer(listingId: listing, amount: 2_500)) {
            assertInvalidState($0, contains: "décliné")
        }
        // A refused negotiation never changes the price used at checkout.
        let order = try await state.createOrder(listingId: listing, delivery: .relais, payment: .wave)
        XCTAssertEqual(order.itemPrice, 8_000)
    }

    // MARK: Seller side (respondToOffer)

    func testSellerRefusalClosesThreadForBuyer() async throws {
        let state = makeState()
        // Awa (seller of listing 7) refuses Karim's 2 000 offer.
        let t = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .refuse, amount: nil)
        XCTAssertEqual(t.status, .refused)
        XCTAssertEqual(t.rounds.last?.action, .refuse)

        // Karim signs in and can no longer make an offer on that listing.
        try await state.sendOTP(phone: "+225" + karimPhone)
        let karim = try await state.verifyOTP(phone: "+225" + karimPhone, code: DemoIDs.otpCode)
        XCTAssertEqual(karim?.id, DemoIDs.karim)
        await assertThrowsAsync(try await state.makeOffer(listingId: DemoIDs.listing(7), amount: 2_250)) {
            assertInvalidState($0, contains: "décliné")
        }
    }

    func testSellerCounterMustBeBetweenOfferAndPrice() async throws {
        let state = makeState()
        let id = DemoIDs.offerRobeFille   // Karim offered 2 000 on a 2 500 listing
        await assertThrowsAsync(try await state.respondToOffer(threadId: id, action: .counter, amount: 2_000)) {
            assertInvalidState($0, contains: "contre-offre doit être entre")
        }
        await assertThrowsAsync(try await state.respondToOffer(threadId: id, action: .counter, amount: 2_500)) {
            assertInvalidState($0, contains: "contre-offre doit être entre")
        }
        await assertThrowsAsync(try await state.respondToOffer(threadId: id, action: .counter, amount: nil)) {
            assertInvalidState($0, contains: "contre-offre doit être entre")
        }
        let t = try await state.respondToOffer(threadId: id, action: .counter, amount: 2_250)
        XCTAssertEqual(t.status, .pending)
        XCTAssertEqual(t.lastSellerCounter?.amount, 2_250)
        // Waiting for the buyer now: a second answer is rejected.
        await assertThrowsAsync(try await state.respondToOffer(threadId: id, action: .accept, amount: nil)) {
            assertInvalidState($0, contains: "Aucune offre en attente")
        }
    }

    func testSellerAcceptSetsAcceptedAmount() async throws {
        let state = makeState()
        let t = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .accept, amount: nil)
        XCTAssertEqual(t.status, .accepted)
        XCTAssertEqual(t.acceptedAmount, 2_000)
    }

    func testOnlySellerCanRespond() async {
        let state = makeState()
        // Awa is the buyer on the Boubou thread.
        await assertThrowsAsync(try await state.respondToOffer(threadId: DemoIDs.offerBoubou, action: .accept, amount: nil)) {
            assertInvalidState($0, contains: "Seule la vendeuse")
        }
    }

    func testOfferThreadsByRole() async throws {
        let repo = DemoRepository()
        let asBuyer = try await repo.offerThreads(role: .buyer)
        let asSeller = try await repo.offerThreads(role: .seller)
        XCTAssertEqual(asBuyer.map(\.id), [DemoIDs.offerBoubou])
        XCTAssertEqual(asSeller.map(\.id), [DemoIDs.offerRobeFille])
    }
}
