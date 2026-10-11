import XCTest
@testable import ReFripe

/// `Fmt` formatting, model helpers, catalogue labels and `AppConfig` parsing.
final class FormattingAndModelTests: XCTestCase {

    // MARK: Fmt.fcfa / Fmt.number

    func testFcfaGroupsThousandsWithNarrowNoBreakSpace() {
        XCTAssertEqual(Fmt.fcfa(4_500), "4\(nnbsp)500 FCFA")
        XCTAssertEqual(Fmt.fcfa(10_000), "10\(nnbsp)000 FCFA")
        XCTAssertEqual(Fmt.fcfa(1_250_000), "1\(nnbsp)250\(nnbsp)000 FCFA")
    }

    func testFcfaSmallAmounts() {
        XCTAssertEqual(Fmt.fcfa(0), "0 FCFA")
        XCTAssertEqual(Fmt.fcfa(999), "999 FCFA")
    }

    func testNumber() {
        XCTAssertEqual(Fmt.number(2_000), "2\(nnbsp)000")
        XCTAssertEqual(Fmt.number(42), "42")
    }

    // MARK: Fmt.relative / Fmt.seniority

    func testRelative() {
        let now = Date()
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-20), now: now), "À l'instant")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-5 * 60), now: now), "Il y a 5 min")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-3 * 86_400), now: now), "Il y a 3 jours")
        let old = Fmt.relative(now.addingTimeInterval(-40 * 86_400), now: now)
        XCTAssertFalse(old.hasPrefix("Il y a"), "older than a week → absolute date, got \(old)")
    }

    func testSeniority() {
        let now = Date()
        let cal = Calendar.current
        func monthsAgo(_ m: Int) -> Date { cal.date(byAdding: .month, value: -m, to: now)! }
        XCTAssertEqual(Fmt.seniority(since: now, now: now), "Nouveau")
        XCTAssertEqual(Fmt.seniority(since: monthsAgo(8), now: now), "8 mois")
        XCTAssertEqual(Fmt.seniority(since: monthsAgo(12), now: now), "1 an")
        XCTAssertEqual(Fmt.seniority(since: monthsAgo(30), now: now), "2 ans")
    }

    // MARK: Models

    func testListingHelpers() {
        let boubou = seedListing(4)
        XCTAssertEqual(boubou.priceDrop, 2_000)
        XCTAssertEqual(boubou.locationLabel, "Plateau, Dakar")
        XCTAssertNil(seedListing(3).priceDrop)
        var l = seedListing(3)
        l.oldPrice = 7_000   // "old" price below current → no drop badge
        XCTAssertNil(l.priceDrop)
    }

    func testOfferThreadHelpers() {
        let t = DemoSeed.make().threads.first { $0.id == DemoIDs.offerBoubou }!
        XCTAssertEqual(t.buyerOfferCount, 1)
        XCTAssertEqual(t.lastBuyerOffer?.amount, 7_000)
        XCTAssertEqual(t.lastSellerCounter?.amount, 8_500)
        XCTAssertNil(t.acceptedAmount, "pending thread has no accepted amount")
    }

    func testSizeLabels() {
        XCTAssertEqual(SizeType.haut.displayLabel(for: "M"), "Taille M")
        XCTAssertEqual(SizeType.pantalon.displayLabel(for: "38"), "Taille 38")
        XCTAssertEqual(SizeType.chaussures.displayLabel(for: "42"), "Pointure 42")
        XCTAssertEqual(SizeType.enfant.displayLabel(for: "4 ans"), "4 ans")
        XCTAssertEqual(SizeType.chaussures.options.count, 10)
        XCTAssertEqual(SizeType.unique.options, ["Taille unique"])
    }

    func testUserProfileHelpers() {
        let awa = DemoSeed.make().profiles[DemoIDs.awa]!
        XCTAssertEqual(awa.initial, "A")
        XCTAssertEqual(awa.locationLabel, "Abidjan, Cocody")
    }

    func testListingDraftResolvedBrand() {
        var d = ListingDraft()
        XCTAssertEqual(d.resolvedBrand, "")
        d.brand = "Nike"
        XCTAssertEqual(d.resolvedBrand, "Nike")
        d.brand = "Autre"
        d.brandCustom = "Maison Wax"
        XCTAssertEqual(d.resolvedBrand, "Maison Wax")
    }

    func testDemoIDsAreDeterministic() {
        XCTAssertEqual(DemoIDs.listing(4).uuidString, "A0000000-0000-0000-0000-000000000004")
        XCTAssertEqual(DemoIDs.allListings.count, 9)
        XCTAssertEqual(Set(DemoIDs.allListings).count, 9)
    }

    // MARK: AppConfig

    func testAppConfigRequiresBothKeys() {
        XCTAssertNil(AppConfig.load(from: nil))
        XCTAssertNil(AppConfig.load(from: [:]))
        XCTAssertNil(AppConfig.load(from: ["SUPABASE_URL": "https://x.supabase.co", "SUPABASE_ANON_KEY": "  "]))
        XCTAssertNil(AppConfig.load(from: ["SUPABASE_URL": "$(SUPABASE_URL)", "SUPABASE_ANON_KEY": "$(SUPABASE_ANON_KEY)"]))
    }

    func testAppConfigValidatesURL() {
        XCTAssertNil(AppConfig.load(from: ["SUPABASE_URL": "ftp://x.supabase.co", "SUPABASE_ANON_KEY": "k"]))
        XCTAssertNil(AppConfig.load(from: ["SUPABASE_URL": "not a url", "SUPABASE_ANON_KEY": "k"]))
        let c = AppConfig.load(from: ["SUPABASE_URL": " https://abc.supabase.co ", "SUPABASE_ANON_KEY": "anon"])
        XCTAssertEqual(c?.url.host, "abc.supabase.co")
        XCTAssertEqual(c?.anonKey, "anon")
    }

    func testCIBuildRunsInDemoMode() {
        // No Supabase keys in CI → the app (and these tests) use DemoRepository.
        XCTAssertNil(AppConfig.supabase)
    }
}
