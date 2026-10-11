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
