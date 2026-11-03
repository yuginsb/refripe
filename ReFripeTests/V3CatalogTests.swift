import XCTest
@testable import ReFripe

/// v3 catalogue rules in the demo repository: item type / size / district filters, "15 000 +" = no upper
/// bound, own listings excluded, private `minOffer` never leaves the seller, 2 h reservation, catalog helpers.
/// Awa is signed in (her listings: 1, 5, 7).
final class V3CatalogTests: XCTestCase {

    private func ids(_ listings: [Listing]) -> Set<UUID> { Set(listings.map(\.id)) }
    private func set(_ ns: Int...) -> Set<UUID> { Set(ns.map { DemoIDs.listing($0) }) }

    private func feedIds(_ repo: DemoRepository, _ f: ListingFilters) async throws -> Set<UUID> {
        ids(try await repo.feed(filters: f, preferences: nil))
    }

    // MARK: Filters

    func testItemTypeFilter() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.itemTypes = [.robe]
        let robes = try await feedIds(repo, f)
        XCTAssertEqual(robes, set(4), "robes 1 and 7 are Awa's own")
        f.itemTypes = [.ensemble]
        let ensembles = try await feedIds(repo, f)
        XCTAssertEqual(ensembles, set(8, 9))
        f.itemTypes = [.chaussures, .sac]
        let mixed = try await feedIds(repo, f)
        XCTAssertEqual(mixed, set(3, 6))
        f.itemTypes = [.jupe]
        let none = try await feedIds(repo, f)
        XCTAssertTrue(none.isEmpty)
    }

    func testEveryDemoListingHasASensibleItemType() {
        let types = Dictionary(uniqueKeysWithValues: DemoSeed.make().listings.map { ($0.id, $0.itemType) })
        XCTAssertEqual(types[DemoIDs.listing(1)], .robe)
        XCTAssertEqual(types[DemoIDs.listing(2)], .chemise)
        XCTAssertEqual(types[DemoIDs.listing(3)], .chaussures)
        XCTAssertEqual(types[DemoIDs.listing(5)], .jean)
        XCTAssertEqual(types[DemoIDs.listing(6)], .sac)
        XCTAssertFalse(types.values.contains(.autre))
    }

    func testSizeFilterMatchesRawSizeValue() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.sizes = ["42"]                       // "Pointure 42"
        let shoes = try await feedIds(repo, f)
        XCTAssertEqual(shoes, set(3))
        f.sizes = ["L"]                        // "Taille L"
        let large = try await feedIds(repo, f)
        XCTAssertEqual(large, set(2))
        f.sizes = ["taille unique"]            // case-insensitive
        let unique = try await feedIds(repo, f)
        XCTAssertEqual(unique, set(4, 6))
        f.sizes = ["6 ans", "0-3 mois"]
        let kids = try await feedIds(repo, f)
        XCTAssertEqual(kids, set(8, 9))
        f.sizes = ["M"]                        // only Awa's own robe is M
        let mine = try await feedIds(repo, f)
        XCTAssertTrue(mine.isEmpty)
    }

    func testListingSizeValueIsDerivedFromLabel() {
        XCTAssertEqual(seedListing(1).sizeValue, "M")
        XCTAssertEqual(seedListing(3).sizeValue, "42")
        XCTAssertEqual(seedListing(5).sizeValue, "38")
        XCTAssertEqual(seedListing(4).sizeValue, "Taille unique")
        XCTAssertEqual(seedListing(7).sizeValue, "4 ans")
        XCTAssertTrue(seedListing(3).matchesSize([]), "no size filter = any size")
        XCTAssertTrue(seedListing(1).matchesSize(["m", "L"]))
        XCTAssertFalse(seedListing(1).matchesSize(["S"]))
    }

    func testDistrictFilter() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.districts = ["Plateau"]              // Plateau exists in Abidjan (2) and Dakar (4, 9)
        let plateau = try await feedIds(repo, f)
        XCTAssertEqual(plateau, set(2, 4, 9))
        f.districts = ["Yopougon", "Almadies"]
        let two = try await feedIds(repo, f)
        XCTAssertEqual(two, set(3, 6, 8))
        f.districts = ["Cocody"]               // only Awa's listings
        let cocody = try await feedIds(repo, f)
        XCTAssertTrue(cocody.isEmpty)
    }

    func testCombinedV3Filters() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.itemTypes = [.ensemble, .chemise]
        f.districts = ["Yopougon", "Plateau"]
        f.priceMax = 2_000
        let result = try await feedIds(repo, f)
        XCTAssertEqual(result, set(2, 8, 9))
    }

    func testTopOfPriceSliderMeansNoUpperBound() async throws {
        var seed = DemoSeed.make()
        let i = seed.listings.firstIndex { $0.id == DemoIDs.listing(4) }!
        seed.listings[i].price = 25_000        // above catalogMaxPrice (15 000)
        let state = DemoState(seed: seed)
        var f = ListingFilters()
        XCTAssertEqual(f.priceMax, ListingFilters.catalogMaxPrice)
        let unbounded = await state.feed(filters: f, preferences: nil)
        XCTAssertTrue(unbounded.contains { $0.id == DemoIDs.listing(4) }, "\"15 000 +\" has no upper bound")
        f.priceMax = 14_000
        let bounded = await state.feed(filters: f, preferences: nil)
        XCTAssertFalse(bounded.contains { $0.id == DemoIDs.listing(4) })
    }

    func testV3FiltersCountInActiveCount() {
        var f = ListingFilters()
        f.itemTypes = [.robe, .jupe]
        f.sizes = ["M"]
        f.districts = ["Cocody", "Plateau"]
        XCTAssertEqual(f.activeCount, 3)
    }

    // MARK: Own listings, minOffer

    func testOwnListingsAreExcludedFromFeedAndSwipeButNotFromMyDressing() async throws {
        let repo = DemoRepository()
        var d = ListingDraft()
        d.photos = [Data([0xFF, 0xD8, 0xFF])]
        d.gender = .femme
        d.itemType = .jupe
        d.sizeType = .pantalon
        d.sizeValue = "38"
        d.condition = .good
        d.price = 2_500
        let mine = try await repo.publish(d)
        XCTAssertEqual(mine.itemType, .jupe)
        XCTAssertEqual(mine.title, "Jupe", "no title → item type label")

        let feed = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertFalse(feed.contains { $0.sellerId == DemoIDs.awa })
        let deck = try await repo.swipeDeck(preferences: nil)
        XCTAssertFalse(deck.contains { $0.sellerId == DemoIDs.awa })
        let dressing = try await repo.listings(sellerId: DemoIDs.awa)
        XCTAssertEqual(dressing.first?.id, mine.id)
    }

    func testMinOfferIsStrippedForBuyers() async throws {
        let repo = DemoRepository()
        let baskets = try await repo.listing(id: DemoIDs.listing(3))     // SneakDak, floor 6 000
        XCTAssertTrue(baskets.negotiable)
        XCTAssertNil(baskets.minOffer, "another seller's floor must never reach the buyer")
        let feed = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertTrue(feed.allSatisfy { $0.minOffer == nil })
        let deck = try await repo.swipeDeck(preferences: nil)
        XCTAssertTrue(deck.allSatisfy { $0.minOffer == nil })
        let sneak = try await repo.listings(sellerId: DemoIDs.sneak)
        XCTAssertTrue(sneak.allSatisfy { $0.minOffer == nil })

        // The seller still sees her own floor.
        let own = try await repo.listing(id: DemoIDs.listing(1))
        XCTAssertEqual(own.minOffer, 3_500)
        // The offer composer therefore no longer clamps to the hidden floor.
        XCTAssertEqual(OfferRules.initialDraft(listing: baskets, thread: nil), 6_000)
    }

    // MARK: 2 h reservation

    func testAcceptedOfferReservesTheListingTwoHoursForThatBuyer() async throws {
        let clock = TestClock()
        let state = makeDemoState(clock: clock)
        // Awa (seller of listing 7) accepts Karim's 2 000 offer.
        _ = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .accept, amount: nil)
        let reserved = try await state.listing(id: DemoIDs.listing(7))
        XCTAssertEqual(reserved.reservedFor, DemoIDs.karim)
        XCTAssertEqual(reserved.reservedUntil, clock.now.addingTimeInterval(Catalog.reservationDuration))
        XCTAssertEqual(reserved.status, .active)

        // Another buyer is refused while the reservation holds.
        try await signIn(state, phone: TestPhones.sneak)
        await assertThrowsAsync(try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "Réservé pour une autre acheteuse jusqu'à")
        }

        // After 2 h the item is free again.
        clock.advance(by: Catalog.reservationDuration + 60)
        let free = try await state.listing(id: DemoIDs.listing(7))
        XCTAssertNil(free.reservedUntil)
        XCTAssertNil(free.reservedFor)
        let order = try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .relais, payment: .wave)
        XCTAssertEqual(order.buyerId, DemoIDs.sneak)
        XCTAssertEqual(order.itemPrice, 2_500, "no accepted offer for this buyer → listed price")
    }

    func testReservedBuyerCanBuyAtTheNegotiatedPrice() async throws {
        let state = makeDemoState()
        _ = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .accept, amount: nil)
        try await signIn(state, phone: TestPhones.karim)
        let order = try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .mainPropre, payment: .orangeMoney)
        XCTAssertEqual(order.itemPrice, 2_000)
        let listing = try await state.listing(id: DemoIDs.listing(7))
        XCTAssertEqual(listing.status, .reserved)
        XCTAssertEqual(listing.reservedFor, DemoIDs.karim, "kept while the order is open")
    }

    func testCancelAndReorderKeepsTheReservationForTheSameBuyer() async throws {
        let state = makeDemoState()
        _ = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .accept, amount: nil)
        try await signIn(state, phone: TestPhones.karim)
        let first = try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .relais, payment: .wave)
        // Payment-method switch: cancel the pending order, re-create it with Orange Money.
        let cancelled = try await state.advanceOrder(id: first.id, to: .cancelled)
        XCTAssertEqual(cancelled.status, .cancelled)
        let freed = try await state.listing(id: DemoIDs.listing(7))
        XCTAssertEqual(freed.status, .active)
        XCTAssertEqual(freed.reservedFor, DemoIDs.karim)
        // Still refused to others…
        try await signIn(state, phone: TestPhones.sneak)
        await assertThrowsAsync(try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .relais, payment: .wave)) {
            assertInvalidState($0, contains: "Réservé pour une autre acheteuse")
        }
        // …and Karim re-orders at the negotiated price.
        try await signIn(state, phone: TestPhones.karim)
        let second = try await state.createOrder(listingId: DemoIDs.listing(7), delivery: .relais, payment: .orangeMoney)
        XCTAssertEqual(second.itemPrice, 2_000)
        XCTAssertEqual(second.payment, .orangeMoney)
    }

    func testBuyerAcceptingACounterReservesTheListing() async throws {
        let clock = TestClock()
        let state = makeDemoState(clock: clock)
        // Seed: Fatou countered 8 500 on the Boubou; Awa meets it.
        let t = try await state.makeOffer(listingId: DemoIDs.listing(4), amount: 8_500)
        XCTAssertEqual(t.status, .accepted)
        let boubou = try await state.listing(id: DemoIDs.listing(4))
        XCTAssertEqual(boubou.reservedFor, DemoIDs.awa)
        XCTAssertTrue(boubou.isReserved(forSomeoneOtherThan: DemoIDs.karim, at: clock.now))
        XCTAssertFalse(boubou.isReserved(forSomeoneOtherThan: DemoIDs.awa, at: clock.now))
    }

    func testSellerCannotAcceptASecondBuyerWhileReserved() async throws {
        let extra = OfferThread(id: UUID(), listingId: DemoIDs.listing(7), buyerId: DemoIDs.sneak, sellerId: DemoIDs.awa,
                                rounds: [OfferRound(by: .buyer, amount: 2_250, action: .offer, at: .now)],
                                status: .pending, updatedAt: .now)
        var seed = DemoSeed.make()
        seed.threads.append(extra)
        let state = DemoState(seed: seed)
        _ = try await state.respondToOffer(threadId: DemoIDs.offerRobeFille, action: .accept, amount: nil)
        await assertThrowsAsync(try await state.respondToOffer(threadId: extra.id, action: .accept, amount: nil)) {
            assertInvalidState($0, contains: "déjà réservé")
        }
    }

    func testSellerBotAcceptanceReservesAndSendsOfferAccepted() async throws {
        let repo = DemoRepository()
        _ = try await repo.makeOffer(listingId: DemoIDs.listing(3), amount: 7_500)
        let accepted = await eventually { (try? await repo.offerThread(listingId: DemoIDs.listing(3)))?.status == .accepted }
        XCTAssertTrue(accepted)
        let listing = try await repo.listing(id: DemoIDs.listing(3))
        XCTAssertEqual(listing.reservedFor, DemoIDs.awa)
        let notifs = try await repo.notifications()
        XCTAssertTrue(notifs.contains { $0.kind == .offerAccepted && $0.listingId == DemoIDs.listing(3) })
    }

    // MARK: Catalog helpers

    func testItemTypeAndReportReasonLabels() {
        XCTAssertEqual(ItemType.allCases.count, 12)
        XCTAssertEqual(Set(ItemType.allCases.map(\.label)).count, 12)
        XCTAssertEqual(ItemType.robe.label, "Robe")
        XCTAssertEqual(ItemType.chaussures.label, "Chaussures")
        XCTAssertEqual(ItemType.jean.suggestedSizeType, .pantalon)
        XCTAssertNil(ItemType.autre.suggestedSizeType)
        XCTAssertEqual(Set(ReportReason.allCases.map(\.label)).count, ReportReason.allCases.count)
        XCTAssertFalse(ReportReason.allCases.contains { $0.label.isEmpty })
    }

    func testCatalogConstants() {
        XCTAssertEqual(Catalog.budgetPresets, [2_000, 5_000, 10_000])
        XCTAssertEqual(Catalog.districts(in: "Abidjan").count, 10)
        XCTAssertEqual(Catalog.districts(in: "Abidjan").first, "Cocody")
        XCTAssertEqual(Catalog.districts(in: "Dakar").count, 8)
        XCTAssertTrue(Catalog.districts(in: "Dakar").contains("Point E"))
        XCTAssertTrue(Catalog.districts(in: "Paris").isEmpty)
        XCTAssertEqual(Catalog.cities.sorted(), Catalog.districts.keys.sorted())
        XCTAssertEqual(Catalog.reservationDuration, 7_200)
        XCTAssertEqual(Catalog.escrowAutoReleaseHours, 72)
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 3; c.hour = 9; c.minute = 5
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(Fmt.hourMinute(date), "09:05")
    }

    func testNotificationKindsMatchTheSQLEnum() {
        XCTAssertEqual(NotificationKind(rawValue: "offer_received"), .offerReceived)
        XCTAssertEqual(NotificationKind(rawValue: "offer_accepted"), .offerAccepted)
        XCTAssertEqual(NotificationKind(rawValue: "offer_refused"), .offerRefused)
        XCTAssertEqual(NotificationKind(rawValue: "new_sale"), .newSale)
        XCTAssertEqual(ItemType(rawValue: "accessoire"), .accessoire)
    }
}
