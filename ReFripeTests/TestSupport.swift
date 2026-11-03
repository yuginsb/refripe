import XCTest
@testable import ReFripe

// MARK: - Async helpers shared by the unit tests

/// Asserts that an async expression throws, and hands the error to `check` for further assertions.
func assertThrowsAsync<T>(_ expression: @autoclosure () async throws -> T,
                          _ message: String = "expected an error",
                          file: StaticString = #filePath, line: UInt = #line,
                          _ check: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail(message, file: file, line: line)
    } catch {
        check(error)
    }
}

/// Polls `condition` every 100 ms until it is true or `timeout` elapses (demo bots answer after 1–2 s).
func eventually(timeout: TimeInterval = 8, _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let ok = try await condition()
        if ok { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return try await condition()
}

/// `RepositoryError.invalidState` whose message contains `fragment`.
func assertInvalidState(_ error: Error, contains fragment: String,
                        file: StaticString = #filePath, line: UInt = #line) {
    guard case RepositoryError.invalidState(let message) = error else {
        return XCTFail("expected invalidState(\"…\(fragment)…\"), got \(error)", file: file, line: line)
    }
    XCTAssertTrue(message.contains(fragment), "“\(message)” does not contain “\(fragment)”", file: file, line: line)
}

func assertOfferLimitReached(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    guard case RepositoryError.offerLimitReached = error else {
        return XCTFail("expected offerLimitReached, got \(error)", file: file, line: line)
    }
}

func assertNotFound(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    guard case RepositoryError.notFound = error else {
        return XCTFail("expected notFound, got \(error)", file: file, line: line)
    }
}

/// Demo listings by mockup id (1…9).
func seedListing(_ n: Int) -> Listing {
    DemoSeed.make().listings.first { $0.id == DemoIDs.listing(n) }!
}

/// Narrow no-break space used by `Fmt` as the thousands separator.
let nnbsp = "\u{202F}"

// MARK: - v3 helpers

/// Extra demo phone numbers (OTP code `DemoIDs.otpCode`) to sign in as other members.
enum TestPhones {
    static let karim = "0101010101"
    static let fatouK = "0202020202"
    static let sneak = "0303030303"
}

/// Mutable clock injected into `DemoState` / `DemoRepository` (2 h reservation, 72 h escrow).
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date()) { current = start }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// Demo state with the extra phones, a controllable clock and fast payment (no simulated shipping by default).
func makeDemoState(clock: TestClock = TestClock(), paymentDelay: Double = 0.2, shipDelay: Double? = nil) -> DemoState {
    var seed = DemoSeed.make()
    seed.phones[TestPhones.karim] = DemoIDs.karim
    seed.phones[TestPhones.fatouK] = DemoIDs.fatouK
    seed.phones[TestPhones.sneak] = DemoIDs.sneak
    return DemoState(seed: seed, clock: { clock.now }, paymentDelay: paymentDelay, shipDelay: shipDelay)
}

/// Signs `state` in as the member owning `phone` (demo OTP).
func signIn(_ state: DemoState, phone: String, file: StaticString = #filePath, line: UInt = #line) async throws {
    let profile = try await state.verifyOTP(phone: phone, code: DemoIDs.otpCode)
    XCTAssertNotNil(profile, "no demo member for \(phone)", file: file, line: line)
}
