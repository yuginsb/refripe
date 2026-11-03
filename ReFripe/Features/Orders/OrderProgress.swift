import Foundation

/// Countdown labels for the escrow release (« 2 j 14 h », « 5 h 12 min », « 12 min »).
enum EscrowCountdown {
    static func text(until date: Date, now: Date = .now) -> String? {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days) j \(hours) h" : "\(days) j" }
        if hours > 0 { return mins > 0 ? "\(hours) h \(mins) min" : "\(hours) h" }
        return "\(max(1, mins)) min"
    }
}

/// The 4 steps shown to people (Payé · Expédié · Remis · Terminé), mapped from the 11 statuses.
enum OrderStep: Int, CaseIterable, Hashable {
    case paid, shipped, handedOff, completed

    var title: String {
        switch self {
        case .paid: "Payé"
        case .shipped: "Expédié"
        case .handedOff: "Remis"
        case .completed: "Terminé"
        }
    }

    /// Status that marks this step as done (for dates in the history).
    var doneStatuses: [OrderStatus] {
        switch self {
        case .paid: [.paid, .awaitingShipment]
        case .shipped: [.shipped]
        case .handedOff: [.delivered, .buyerValidation]
        case .completed: [.completed]
        }
    }

    /// Number of steps done for a happy-path status.
    static func doneCount(for status: OrderStatus) -> Int {
        switch status {
        case .paymentPending: 0
        case .paid, .awaitingShipment: 1
        case .shipped: 2
        case .delivered, .buyerValidation: 3
        case .completed: 4
        case .cancelled, .disputed, .returnPending, .refunded: 0
        }
    }

    /// Steps done for any order: alternative outcomes keep what was reached before diverging.
    static func doneCount(for order: Order) -> Int {
        guard order.status.isAlternative else { return doneCount(for: order.status) }
        return order.history.map { doneCount(for: $0.status) }.max() ?? 0
    }

    func date(in order: Order) -> Date? {
        order.history.last(where: { doneStatuses.contains($0.status) })?.at
    }
}

extension Order {
    /// Short order number: "#1" for demo ids, "#3FA2B9" for random UUIDs.
    var shortNumber: String {
        let tail = id.uuidString.suffix(6).drop(while: { $0 == "0" })
        return "#" + (tail.isEmpty ? "0" : String(tail))
    }

    /// Buyer still has to confirm reception (escrow countdown running).
    var awaitsBuyerConfirmation: Bool { status == .delivered || status == .buyerValidation }
    /// Seller has to ship / hand over.
    var awaitsShipping: Bool { status == .paid || status == .awaitingShipment }
}
