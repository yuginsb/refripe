import XCTest
@testable import ReFripe

/// Pure negotiation rules from `Catalog.swift` (`OfferRules`), shared by the buyer UI and the demo seller bot.
final class OfferRulesTests: XCTestCase {

    func testMaxBuyerOffersIsThree() {
        XCTAssertEqual(OfferRules.maxBuyerOffers, 3)
    }

    func testStepIs250Below6000And500From6000() {
        XCTAssertEqual(OfferRules.step(for: 0), 250)
        XCTAssertEqual(OfferRules.step(for: 2_500), 250)
        XCTAssertEqual(OfferRules.step(for: 5_999), 250)
        XCTAssertEqual(OfferRules.step(for: 6_000), 500)
        XCTAssertEqual(OfferRules.step(for: 15_000), 500)
    }

    func testRoundGoesToNearestStepHalfUp() {
        XCTAssertEqual(OfferRules.round(7_750, step: 500), 8_000)   // exactly half → up
        XCTAssertEqual(OfferRules.round(7_740, step: 500), 7_500)
        XCTAssertEqual(OfferRules.round(3_375, step: 250), 3_500)
        XCTAssertEqual(OfferRules.round(3_374, step: 250), 3_250)
        XCTAssertEqual(OfferRules.round(0, step: 250), 0)
        XCTAssertEqual(OfferRules.round(6_000, step: 500), 6_000)
    }

    // MARK: initialDraft

    func testInitialDraftWithoutThreadIs75PercentClampedToSellerFloor() {
        // Baskets Nike: 8 000, floor 6 000 → 75 % = 6 000.
        XCTAssertEqual(OfferRules.initialDraft(listing: seedListing(3), thread: nil), 6_000)
        // Robe wax: 4 500, floor 3 500 → 75 % = 3 375 → rounded to 3 500 (step 250).
        XCTAssertEqual(OfferRules.initialDraft(listing: seedListing(1), thread: nil), 3_500)
        // Sac cuir: 6 500, floor 5 000 → 4 875 → 5 000.
        XCTAssertEqual(OfferRules.initialDraft(listing: seedListing(6), thread: nil), 5_000)
    }

    func testInitialDraftIsRaisedToSellerFloor() {
        var l = seedListing(3)
        l.minOffer = 7_000
        XCTAssertEqual(OfferRules.initialDraft(listing: l, thread: nil), 7_000)
    }

    func testInitialDraftNeverReachesListedPrice() {
        var l = seedListing(3)
        l.price = 1_000
        l.minOffer = nil
        // 750 = price − step (250).
        XCTAssertEqual(OfferRules.initialDraft(listing: l, thread: nil), 750)
        XCTAssertLessThan(OfferRules.initialDraft(listing: l, thread: nil), l.price)
    }

    func testInitialDraftWithCounterIsMidpointOfLastOfferAndCounter() {
        let thread = DemoSeed.make().threads.first { $0.id == DemoIDs.offerBoubou }!
        // Boubou 10 000: buyer 7 000, seller counter 8 500 → midpoint 7 750 → 8 000 (step 500).
        XCTAssertEqual(OfferRules.initialDraft(listing: seedListing(4), thread: thread), 8_000)
    }

    // MARK: simulatedSellerResponse (demo seller bot)

    private func thread(on listing: Listing, buyerOffers amounts: [FCFA]) -> OfferThread {
        var rounds: [OfferRound] = []
        for (i, a) in amounts.enumerated() {
            if i > 0 { rounds.append(OfferRound(by: .seller, amount: listing.price - 500, action: .counter, at: .now)) }
            rounds.append(OfferRound(by: .buyer, amount: a, action: .offer, at: .now))
        }
        return OfferThread(id: UUID(), listingId: listing.id, buyerId: DemoIDs.awa, sellerId: listing.sellerId,
                           rounds: rounds, status: .pending, updatedAt: .now)
    }

    func testSellerBotAcceptsOfferAtNinetyPercent() {
        let l = seedListing(3)   // 8 000 → 90 % = 7 200 → rounded 7 000
        let (action, amount) = OfferRules.simulatedSellerResponse(listing: l, thread: thread(on: l, buyerOffers: [7_000]))
        XCTAssertEqual(action, .accept)
        XCTAssertEqual(amount, 7_000)
    }

    func testSellerBotCountersHalfwayOnLowFirstOffer() {
        let l = seedListing(3)
        let (action, amount) = OfferRules.simulatedSellerResponse(listing: l, thread: thread(on: l, buyerOffers: [6_000]))
        XCTAssertEqual(action, .counter)
        XCTAssertEqual(amount, 7_000)   // (6 000 + 8 000) / 2
        XCTAssertGreaterThan(amount, 6_000)
        XCTAssertLessThan(amount, l.price)
    }

    func testSellerBotCounterStaysStrictlyBetweenOfferAndPrice() {
        let l = seedListing(6)   // 6 500, step 500
        let (action, amount) = OfferRules.simulatedSellerResponse(listing: l, thread: thread(on: l, buyerOffers: [4_000]))
        XCTAssertEqual(action, .counter)
        XCTAssertEqual(amount, 5_500)   // (4 000 + 6 500) / 2 = 5 250 → 5 500
    }

    func testSellerBotDecidesOnThirdOfferUsingFloor() {
        let l = seedListing(3)   // floor 6 000
        let accept = OfferRules.simulatedSellerResponse(listing: l, thread: thread(on: l, buyerOffers: [5_000, 5_500, 6_000]))
        XCTAssertEqual(accept.0, .accept)
        XCTAssertEqual(accept.1, 6_000)
        let refuse = OfferRules.simulatedSellerResponse(listing: l, thread: thread(on: l, buyerOffers: [4_000, 4_500, 5_000]))
        XCTAssertEqual(refuse.0, .refuse)
    }
}
