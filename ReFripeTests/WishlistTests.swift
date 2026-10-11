import XCTest
@testable import ReFripe

/// Wishlist ("Envies"): repository semantics and the optimistic toggle in `AppStore`.
final class WishlistTests: XCTestCase {

    func testSeedWishlist() async throws {
        let repo = DemoRepository()
        let ids = try await repo.wishlistIds()
        XCTAssertEqual(ids, [DemoIDs.listing(2), DemoIDs.listing(4)])
    }

    func testSetLikedIsIdempotentAndUpdatesFavoritesCount() async throws {
        let repo = DemoRepository()
        let id = DemoIDs.listing(3)
        let before = try await repo.listing(id: id).favoritesCount

        try await repo.setLiked(listingId: id, liked: true)
        var ids = try await repo.wishlistIds()
        XCTAssertTrue(ids.contains(id))
        var count = try await repo.listing(id: id).favoritesCount
        XCTAssertEqual(count, before + 1)

        try await repo.setLiked(listingId: id, liked: true)   // already liked → no double count
        count = try await repo.listing(id: id).favoritesCount
        XCTAssertEqual(count, before + 1)

        try await repo.setLiked(listingId: id, liked: false)
        ids = try await repo.wishlistIds()
        XCTAssertFalse(ids.contains(id))
        count = try await repo.listing(id: id).favoritesCount
        XCTAssertEqual(count, before)

        try await repo.setLiked(listingId: id, liked: false)  // already removed → unchanged
        count = try await repo.listing(id: id).favoritesCount
        XCTAssertEqual(count, before)
    }

    func testLikingUnknownListingFails() async {
        let repo = DemoRepository()
        await assertThrowsAsync(try await repo.setLiked(listingId: UUID(), liked: true)) { assertNotFound($0) }
    }

    @MainActor
    func testStoreToggleLikeIsOptimisticAndPersisted() async throws {
        let repo = DemoRepository()
        let store = AppStore(repo: repo, isDemo: true)
        await store.bootstrap()
        XCTAssertTrue(store.isLiked(DemoIDs.listing(2)))
        XCTAssertFalse(store.isLiked(DemoIDs.listing(3)))

        store.toggleLike(DemoIDs.listing(3))
        XCTAssertTrue(store.isLiked(DemoIDs.listing(3)), "UI updates before the repository answers")
        let saved = await eventually { (try? await repo.wishlistIds())?.contains(DemoIDs.listing(3)) == true }
        XCTAssertTrue(saved)

        store.toggleLike(DemoIDs.listing(3))
        XCTAssertFalse(store.isLiked(DemoIDs.listing(3)))
        let removed = await eventually { (try? await repo.wishlistIds())?.contains(DemoIDs.listing(3)) == false }
        XCTAssertTrue(removed)
    }

    @MainActor
    func testStoreToggleLikeRollsBackOnError() async throws {
        let store = AppStore(repo: DemoRepository(), isDemo: true)
        await store.bootstrap()
        let unknown = UUID()
        store.toggleLike(unknown)
        XCTAssertTrue(store.isLiked(unknown))
        let rolledBack = await eventually { !store.isLiked(unknown) }
        XCTAssertTrue(rolledBack, "a failed like is reverted")
        XCTAssertNotNil(store.toast, "and the error is shown")
    }

    @MainActor
    func testBootstrapRestoresDemoSession() async {
        let store = AppStore(repo: DemoRepository(), isDemo: true)
        XCTAssertTrue(store.isBootstrapping)
        await store.bootstrap()
        XCTAssertFalse(store.isBootstrapping)
        XCTAssertEqual(store.me?.id, DemoIDs.awa)
        XCTAssertFalse(store.needsOnboarding)
        XCTAssertGreaterThan(store.unreadNotifications, 0)
        XCTAssertEqual(store.unreadMessages, 1)
    }

    @MainActor
    func testSignedOutStoreNeedsOnboarding() async throws {
        let repo = DemoRepository()
        try await repo.signOut()
        let store = AppStore(repo: repo, isDemo: true)
        await store.bootstrap()
        XCTAssertNil(store.me)
        XCTAssertTrue(store.needsOnboarding)
    }
}
