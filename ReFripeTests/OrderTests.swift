import XCTest
@testable import ReFripe

/// Orders & escrow in the demo repository: creation, totals, payment simulation and status transitions.
/// Seed orders (Awa signed in): 1 = Awa sells, AWAITING_SHIPMENT · 2 = Awa sells, SHIPPED ·
/// 3 = Awa buys, BUYER_VALIDATION · 4, 5 = Awa bought, COMPLETED.
final class OrderTests: XCTestCase {

    // MARK: Delivery fees & totals

    func testDeliveryFees() {
        XCTAssertEqual(DeliveryMethod.relais.fee, 1_000)
        XCTAssertEqual(DeliveryMethod.mainPropre.fee, 0)
        XCTAssertEqual(DeliveryMethod.yango.fee, 2_500)
    }

    func testOrderTotalIsItemPricePlusDeliveryFee() async throws {
        let repo = DemoRepository()
        let yango = try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .yango, payment: .wave)
        XCTAssertEqual(yango.itemPrice, 8_000)
        XCTAssertEqual(yango.deliveryFee, 2_500)
        XCTAssertEqual(yango.total, 10_500)

        let handover = try await repo.createOrder(listingId: DemoIDs.listing(6), delivery: .mainPropre, payment: .orangeMoney)
        XCTAssertEqual(handover.deliveryFee, 0)
        XCTAssertEqual(handover.total, 6_500)

        let relais = try await repo.createOrder(listingId: DemoIDs.listing(9), delivery: .relais, payment: .wave)
        XCTAssertEqual(relais.total, 2_000 + 1_000)
    }

    func testSeedOrderTotals() async throws {
        let repo = DemoRepository()
        let o3 = try await repo.order(id: DemoIDs.order(3))
        XCTAssertEqual(o3.total, 9_000 + 2_500)   // negotiated Boubou, Yango
        let o1 = try await repo.order(id: DemoIDs.order(1))
        XCTAssertEqual(o1.total, 4_500 + 1_000)
    }

    // MARK: Creation rules

    func testCreateOrderReservesListingAndStartsPaymentPending() async throws {
        let repo = DemoRepository()
        let o = try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)
        XCTAssertEqual(o.status, .paymentPending)
        XCTAssertEqual(o.history.map(\.status), [.paymentPending])
        XCTAssertEqual(o.buyerId, DemoIDs.awa)
        XCTAssertEqual(o.sellerId, DemoIDs.sneak)
        let listing = try await repo.listing(id: DemoIDs.listing(3))
        XCTAssertEqual(listing.status, .reserved)
        await assertThrowsAsync(try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "plus disponible")
        }
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 6_000)) {
            assertInvalidState($0, contains: "plus disponible")
        }
    }

    func testCreateOrderRejectsOwnListingAndUnofferedDelivery() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.createOrder(listingId: DemoIDs.listing(1), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "ton propre article")
        }
        // Chemise vintage: hand-over only.
        await assertThrowsAsync(try await repo.createOrder(listingId: DemoIDs.listing(2), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "mode de remise")
        }
        await assertThrowsAsync(try await repo.createOrder(listingId: UUID(), delivery: .relais, payment: .wave)) {
            assertNotFound($0)
        }
    }

    func testAcceptedOfferPriceIsUsedByCreateOrder() async throws {
        let repo = DemoRepository()
        // Boubou 10 000: meeting Fatou's 8 500 counter accepts it.
        _ = try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 8_500)
        let o = try await repo.createOrder(listingId: DemoIDs.listing(4), delivery: .relais, payment: .wave)
        XCTAssertEqual(o.itemPrice, 8_500)
        XCTAssertEqual(o.total, 9_500)
    }

    func testPendingNegotiationDoesNotChangePrice() async throws {
        let repo = DemoRepository()
        // Boubou thread is pending (counter not accepted) → full price.
        let o = try await repo.createOrder(listingId: DemoIDs.listing(4), delivery: .yango, payment: .wave)
        XCTAssertEqual(o.itemPrice, 10_000)
        XCTAssertEqual(o.total, 12_500)
    }

    func testPaymentSimulationFundsEscrow() async throws {
        let repo = DemoRepository()
        let o = try await repo.createOrder(listingId: DemoIDs.listing(6), delivery: .relais, payment: .wave)
        let funded = await eventually { (try? await repo.order(id: o.id))?.status == .awaitingShipment }
        XCTAssertTrue(funded)
        let fresh = try await repo.order(id: o.id)
        XCTAssertEqual(fresh.history.map(\.status), [.paymentPending, .paid, .awaitingShipment])
        let notifs = try await repo.notifications()
        XCTAssertTrue(notifs.contains { $0.orderId == o.id && $0.title == "Paiement confirmé" })
        let buying = try await repo.orders(role: .buyer)
        XCTAssertEqual(buying.first?.id, o.id, "newest order first")
    }

    // MARK: Allowed transitions

    func testBuyerCanCancelBeforeShipment() async throws {
        let repo = DemoRepository()
        let o = try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)
        let cancelled = try await repo.advanceOrder(id: o.id, to: .cancelled)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.history.last?.status, .cancelled)
        let listing = try await repo.listing(id: DemoIDs.listing(3))
        XCTAssertEqual(listing.status, .active, "cancelling puts the item back on sale")
        // The payment bot must not resurrect a cancelled order.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let later = try await repo.order(id: o.id)
        XCTAssertEqual(later.status, .cancelled)
    }

    func testCancelAllowedWhileAwaitingShipment() async throws {
        let repo = DemoRepository()
        let o = try await repo.advanceOrder(id: DemoIDs.order(1), to: .cancelled)
        XCTAssertEqual(o.status, .cancelled)
    }

    func testHappyPathShippedDeliveredValidationCompleted() async throws {
        let repo = DemoRepository()
        var o = try await repo.advanceOrder(id: DemoIDs.order(1), to: .shipped)
        XCTAssertEqual(o.status, .shipped)
        o = try await repo.advanceOrder(id: o.id, to: .delivered)
        XCTAssertEqual(o.status, .delivered)
        o = try await repo.advanceOrder(id: o.id, to: .buyerValidation)
        XCTAssertEqual(o.status, .buyerValidation)
        o = try await repo.advanceOrder(id: o.id, to: .completed)
        XCTAssertEqual(o.status, .completed)
        XCTAssertEqual(o.history.suffix(4).map(\.status), [.shipped, .delivered, .buyerValidation, .completed])
        let listing = try await repo.listing(id: DemoIDs.listing(1))
        XCTAssertEqual(listing.status, .sold)
    }

    func testShippedToDelivered() async throws {
        let repo = DemoRepository()
        let o = try await repo.advanceOrder(id: DemoIDs.order(2), to: .delivered)
        XCTAssertEqual(o.status, .delivered)
    }

    func testValidationToCompletedMarksListingSold() async throws {
        let repo = DemoRepository()
        let o = try await repo.advanceOrder(id: DemoIDs.order(3), to: .completed)
        XCTAssertEqual(o.status, .completed)
        let listing = try await repo.listing(id: DemoIDs.listing(4))
        XCTAssertEqual(listing.status, .sold)
        await assertThrowsAsync(try await repo.makeOffer(listingId: DemoIDs.listing(4), amount: 9_000)) {
            assertInvalidState($0, contains: "plus disponible")
        }
    }

    func testDisputePaths() async throws {
        let repo = DemoRepository()
        // Shipped → dispute → settled for the seller.
        var o = try await repo.advanceOrder(id: DemoIDs.order(2), to: .disputed)
        XCTAssertEqual(o.status, .disputed)
        XCTAssertEqual(o.status.tone, .alert)
        o = try await repo.advanceOrder(id: o.id, to: .completed)
        XCTAssertEqual(o.status, .completed)

        // Buyer validation → dispute → refunded.
        o = try await repo.advanceOrder(id: DemoIDs.order(3), to: .disputed)
        o = try await repo.advanceOrder(id: o.id, to: .refunded)
        XCTAssertEqual(o.status, .refunded)
        XCTAssertEqual(o.status.tone, .cancelled)
    }

    func testReturnPathRefundsAndRelists() async throws {
        let repo = DemoRepository()
        var o = try await repo.advanceOrder(id: DemoIDs.order(3), to: .returnPending)
        XCTAssertEqual(o.status, .returnPending)
        XCTAssertTrue(o.status.isAlternative)
        o = try await repo.advanceOrder(id: o.id, to: .refunded)
        XCTAssertEqual(o.status, .refunded)
        let listing = try await repo.listing(id: DemoIDs.listing(4))
        XCTAssertEqual(listing.status, .active)
    }

    // MARK: Forbidden transitions

    func testCannotCancelAfterShipment() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(2), to: .cancelled)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(3), to: .cancelled)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
    }

    func testCannotSkipSteps() async {
        let repo = DemoRepository()
        // AWAITING_SHIPMENT → DELIVERED / COMPLETED skips shipment.
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(1), to: .delivered)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(1), to: .completed)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
        // SHIPPED → COMPLETED skips delivery and buyer validation.
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(2), to: .completed)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
        // No dispute before shipment, no return before delivery.
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(1), to: .disputed)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(2), to: .returnPending)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
    }

    func testCompletedOrderIsFinal() async {
        let repo = DemoRepository()
        for target in [OrderStatus.cancelled, .disputed, .returnPending, .refunded, .shipped] {
            await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(4), to: target),
                                    "COMPLETED → \(target.rawValue) must be rejected") {
                assertInvalidState($0, contains: "Impossible de passer")
            }
        }
    }

    func testCannotGoBackwards() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.advanceOrder(id: DemoIDs.order(2), to: .awaitingShipment)) {
            assertInvalidState($0, contains: "Impossible de passer")
        }
    }

    func testUnknownOrder() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.advanceOrder(id: UUID(), to: .shipped)) { assertNotFound($0) }
    }

    func testOrdersByRole() async throws {
        let repo = DemoRepository()
        let selling = try await repo.orders(role: .seller).map(\.id)
        let buying = try await repo.orders(role: .buyer).map(\.id)
        XCTAssertEqual(Set(selling), [DemoIDs.order(1), DemoIDs.order(2)])
        XCTAssertEqual(Set(buying), [DemoIDs.order(3), DemoIDs.order(4), DemoIDs.order(5)])
    }

    // MARK: Status metadata

    func testStatusMetadata() {
        XCTAssertEqual(OrderStatus.happyPath.first, .paymentPending)
        XCTAssertEqual(OrderStatus.happyPath.last, .completed)
        for s in [OrderStatus.cancelled, .disputed, .returnPending, .refunded] {
            XCTAssertTrue(s.isAlternative)
            XCTAssertNotNil(s.alternativeInfo)
        }
        XCTAssertFalse(OrderStatus.shipped.isAlternative)
        XCTAssertNil(OrderStatus.shipped.alternativeInfo)
        XCTAssertEqual(OrderStatus.completed.tone, .done)
        XCTAssertEqual(OrderStatus.shipped.tone, .progress)
        XCTAssertLessThan(OrderStatus.disputed.urgencyRank, OrderStatus.awaitingShipment.urgencyRank)
        XCTAssertLessThan(OrderStatus.awaitingShipment.urgencyRank, OrderStatus.shipped.urgencyRank)
        XCTAssertEqual(OrderStatus(rawValue: "BUYER_VALIDATION"), .buyerValidation)
    }
}
