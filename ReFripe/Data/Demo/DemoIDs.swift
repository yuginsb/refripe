import Foundation

/// Deterministic identifiers for the demo dataset (stable across launches, usable in previews and tests).
/// Layout: `KK000000-0000-0000-0000-NNNNNNNNNNNN` where KK is the entity kind and N the mockup id (hex).
/// The last byte equals the mockup id, so `RF.C.thumb(for:)` matches the mockup's `thumbColor(id)`.
enum DemoIDs {
    private static func make(_ kind: UInt8, _ n: Int) -> UUID {
        UUID(uuidString: String(format: "%02X000000-0000-0000-0000-%012lX", kind, n))!
    }

    // MARK: Listings (mockup ids 1…9)
    static func listing(_ n: Int) -> UUID { make(0xA0, n) }
    static let allListings: [UUID] = (1...9).map { listing($0) }

    // MARK: Users
    static let awa = make(0xB0, 1)          // Awa_Style225 — signed-in user in demo mode
    static let karim = make(0xB0, 2)        // Karim_Fripe
    static let sneak = make(0xB0, 3)        // SneakDak
    static let fatou = make(0xB0, 4)        // Fatou_Elegance
    static let second = make(0xB0, 5)      // SecondLook.sn
    static let fatouK = make(0xB0, 6)       // Fatou K. — buyer of order 1, chat partner of Awa

    /// Phone number that signs back in as Awa (`verifyOTP`, code "1234"). Compared on the last 10 digits.
    static let awaPhone = "0707070707"
    static let otpCode = "1234"

    // MARK: Orders (mockup ids 1…5)
    static func order(_ n: Int) -> UUID { make(0xC0, n) }

    // MARK: Conversations
    static let conversationRobeWax = make(0xD0, 1)   // Awa ↔ Fatou K. about listing 1 (mockup chat "awa")
    static let conversationBaskets = make(0xD0, 2)   // Awa ↔ SneakDak about listing 3 (unread reply)

    // MARK: Offer threads
    static let offerBoubou = make(0xE0, 1)           // Awa (buyer) ↔ Fatou_Elegance, listing 4, counter 8 500 pending
    static let offerRobeFille = make(0xE0, 2)        // Karim (buyer) → Awa (seller), listing 7, awaiting Awa

    // MARK: Notifications
    static func notification(_ n: Int) -> UUID { make(0xF0, n) }
}
