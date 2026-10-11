import XCTest
@testable import ReFripe

/// Discover feed filters / sort / swipe deck on the demo catalogue, plus selling & price updates.
/// Demo catalogue: 1 Robe wax 4 500 (Awa) · 2 Chemise 2 000 · 3 Baskets Nike 8 000 · 4 Boubou 10 000 ·
/// 5 Jean 3 000 (Awa) · 6 Sac 6 500 · 7 Robe fille 2 500 (Awa) · 8 Ensemble 1 500 · 9 Pyjama bébé 2 000.
final class CatalogTests: XCTestCase {

    private func ids(_ listings: [Listing]) -> Set<UUID> { Set(listings.map(\.id)) }
    private func set(_ ns: Int...) -> Set<UUID> { Set(ns.map { DemoIDs.listing($0) }) }

    private func expectFeed(_ repo: DemoRepository, _ filters: ListingFilters, _ expected: Set<UUID>,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let got = ids(try await repo.feed(filters: filters, preferences: nil))
        XCTAssertEqual(got, expected, file: file, line: line)
    }

    func testDefaultFeedReturnsAllActiveListings() async throws {
        let repo = DemoRepository()
        let all = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertEqual(all.count, 9)
        // Recent first when no preferences.
        XCTAssertEqual(all.map(\.createdAt), all.map(\.createdAt).sorted(by: >))
    }

    func testCategoryFilter() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.gender = .femme
        try await expectFeed(repo, f, set(1, 4, 5, 6))
        f.gender = .enfant
        try await expectFeed(repo, f, set(7, 8))
        f.gender = .bebe
        try await expectFeed(repo, f, set(9))
    }

    func testPriceRangeIsInclusive() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.priceMin = 2_000
        f.priceMax = 3_000
        try await expectFeed(repo, f, set(2, 5, 7, 9))
        f.priceMin = 6_500
        f.priceMax = ListingFilters.catalogMaxPrice
        try await expectFeed(repo, f, set(3, 4, 6))
    }

    func testNegotiableOnly() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.negotiableOnly = true
        let result = try await repo.feed(filters: f, preferences: nil)
        XCTAssertEqual(ids(result), set(1, 3, 4, 6, 7, 9))
        XCTAssertTrue(result.allSatisfy(\.negotiable))
    }

    func testConditionBrandAndQueryFilters() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.conditions = [.excellent]
        try await expectFeed(repo, f, set(4, 9))

        f = ListingFilters()
        f.brands = ["Vintage"]
        try await expectFeed(repo, f, set(2, 6))

        f = ListingFilters()
        f.query = "  NIKE "
        try await expectFeed(repo, f, set(3))
        f.query = "ceremonie"   // tag "Cérémonie": case and diacritic insensitive
        try await expectFeed(repo, f, set(1))
    }

    func testCombinedFilters() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.gender = .femme
        f.negotiableOnly = true
        f.priceMax = 7_000
        try await expectFeed(repo, f, set(1, 6))
    }

    func testSortOrders() async throws {
        let repo = DemoRepository()
        var f = ListingFilters()
        f.sort = .priceAsc
        let asc = try await repo.feed(filters: f, preferences: nil)
        XCTAssertEqual(asc.map(\.price), asc.map(\.price).sorted())
        XCTAssertEqual(asc.first?.id, DemoIDs.listing(8))

        f.sort = .priceDesc
        let desc = try await repo.feed(filters: f, preferences: nil)
        XCTAssertEqual(desc.map(\.price), desc.map(\.price).sorted(by: >))
        XCTAssertEqual(desc.first?.id, DemoIDs.listing(4))

        f.sort = .popular
        let popular = try await repo.feed(filters: f, preferences: nil)
        XCTAssertEqual(popular.map(\.views), popular.map(\.views).sorted(by: >))
        XCTAssertEqual(popular.first?.id, DemoIDs.listing(3))
    }

    func testRecentSortPutsPreferredCategoriesFirst() async throws {
        let repo = DemoRepository()
        var prefs = UserPreferences()
        prefs.categories = [.enfant]
        let feed = try await repo.feed(filters: ListingFilters(), preferences: prefs)
        XCTAssertEqual(Array(feed.prefix(2)).map(\.id), [DemoIDs.listing(7), DemoIDs.listing(8)])
        XCTAssertEqual(feed.count, 9)
    }

    func testReservedListingsLeaveTheFeed() async throws {
        let repo = DemoRepository()
        _ = try await repo.createOrder(listingId: DemoIDs.listing(3), delivery: .relais, payment: .wave)
        let feed = try await repo.feed(filters: ListingFilters(), preferences: nil)
        XCTAssertFalse(feed.contains { $0.id == DemoIDs.listing(3) })
    }

    func testActiveFilterCount() {
        var f = ListingFilters()
        XCTAssertEqual(f.activeCount, 0)
        f.gender = .homme
        f.query = "nike"
        XCTAssertEqual(f.activeCount, 0, "gender and query are not advanced filters")
        f.priceMin = 1_000
        XCTAssertEqual(f.activeCount, 1)
        f.priceMax = 5_000
        XCTAssertEqual(f.activeCount, 1, "min and max count as one price filter")
        f.negotiableOnly = true
        f.sort = .priceAsc
        f.conditions = [.good]
        f.brands = ["Nike"]
        XCTAssertEqual(f.activeCount, 5)
    }

    // MARK: Swipe deck

    func testSwipeDeckExcludesOwnListingsAndPrefersMyCategories() async throws {
        let repo = DemoRepository()
        var prefs = UserPreferences()
        prefs.categories = [.femme]
        let deck = try await repo.swipeDeck(preferences: prefs)
        XCTAssertFalse(deck.contains { $0.sellerId == DemoIDs.awa })
        XCTAssertEqual(ids(deck), set(2, 3, 4, 6, 8, 9))
        XCTAssertEqual(Array(deck.prefix(2)).map(\.id), [DemoIDs.listing(4), DemoIDs.listing(6)])
    }

    func testSwipedCardsLeaveTheDeck() async throws {
        let repo = DemoRepository()
        try await repo.recordSwipe(listingId: DemoIDs.listing(4), liked: false)
        try await repo.recordSwipe(listingId: DemoIDs.listing(3), liked: true)
        let deck = try await repo.swipeDeck(preferences: nil)
        XCTAssertFalse(deck.contains { $0.id == DemoIDs.listing(4) || $0.id == DemoIDs.listing(3) })
        let wishlist = try await repo.wishlistIds()
        XCTAssertTrue(wishlist.contains(DemoIDs.listing(3)), "swipe right adds to the wishlist")
    }

    // MARK: Selling

    func testPublishValidatesDraft() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.publish(ListingDraft())) { assertInvalidState($0, contains: "photo") }
        var d = ListingDraft()
        d.photos = [Data([0xFF, 0xD8, 0xFF])]
        await assertThrowsAsync(try await repo.publish(d)) { assertInvalidState($0, contains: "catégorie") }
        d.gender = .femme
        d.sizeType = .haut
        await assertThrowsAsync(try await repo.publish(d)) { assertInvalidState($0, contains: "état") }
        d.condition = .good
        d.delivery = []
        await assertThrowsAsync(try await repo.publish(d)) { assertInvalidState($0, contains: "mode de remise") }
    }

    func testPublishCreatesActiveListingWithClampedFloor() async throws {
        let repo = DemoRepository()
        var d = ListingDraft()
        d.photos = [Data([0xFF, 0xD8, 0xFF])]
        d.gender = .femme
        d.brand = "Zara"
        d.sizeType = .chaussures
        d.sizeValue = "39"
        d.condition = .veryGood
        d.price = 3_000
        d.negotiable = true
        d.minOffer = 4_000
        d.delivery = [.yango, .relais]
        let l = try await repo.publish(d)
        XCTAssertEqual(l.title, "Femme · Zara")
        XCTAssertEqual(l.sizeLabel, "Pointure 39")
        XCTAssertEqual(l.minOffer, 3_000, "seller floor is clamped to the price")
        XCTAssertEqual(l.deliveryMethods, [.relais, .yango])
        XCTAssertEqual(l.status, .active)
        XCTAssertEqual(l.sellerId, DemoIDs.awa)
        let mine = try await repo.listings(sellerId: DemoIDs.awa)
        XCTAssertEqual(mine.first?.id, l.id)
    }

    func testPriceDropSetsOldPrice() async throws {
        let repo = DemoRepository()
        var l = try await repo.updatePrice(listingId: DemoIDs.listing(1), price: 4_000)
        XCTAssertEqual(l.oldPrice, 4_500)
        XCTAssertEqual(l.priceDrop, 500)
        XCTAssertEqual(l.minOffer, 3_500)
        l = try await repo.updatePrice(listingId: DemoIDs.listing(1), price: 3_000)
        XCTAssertEqual(l.oldPrice, 4_500, "reference price is the highest one")
        XCTAssertEqual(l.minOffer, 3_000, "floor follows the price down")
        l = try await repo.updatePrice(listingId: DemoIDs.listing(1), price: 5_000)
        XCTAssertNil(l.oldPrice)
        XCTAssertNil(l.priceDrop)
        await assertThrowsAsync(try await repo.updatePrice(listingId: DemoIDs.listing(3), price: 7_000)) {
            assertInvalidState($0, contains: "Seule la vendeuse")
        }
        await assertThrowsAsync(try await repo.updatePrice(listingId: DemoIDs.listing(1), price: 0)) {
            assertInvalidState($0, contains: "prix valide")
        }
    }
}
