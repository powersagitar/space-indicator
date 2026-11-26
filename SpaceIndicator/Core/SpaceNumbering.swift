import Foundation

enum SpaceNumbering {
    /// One entry per display: the 1-based position of its "Current Space" within its own
    /// "Spaces" array, or nil when that can't be trusted. Displays listed in `screenOrder`
    /// (by "Display Identifier") come first, in that order; the rest keep CGS order.
    static func numbers(displays: [[String: Any]], screenOrder: [String]) -> [Int?] {
        var entries: [(id: String?, number: Int?)] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            entries.append((display["Display Identifier"] as? String, number(of: display, in: spaces)))
        }
        let rank = { (id: String?) -> Int in
            id.flatMap { screenOrder.firstIndex(of: $0) } ?? screenOrder.count
        }
        // Stable: unknown IDs share the last rank and keep CGS order.
        let sorted = entries.enumerated().sorted {
            (rank($0.element.id), $0.offset) < (rank($1.element.id), $1.offset)
        }
        return sorted.map { $0.element.number }
    }

    static func title(for numbers: [Int?]) -> String {
        guard !numbers.isEmpty else { return "?" }
        return numbers.map { $0.map { "\($0)" } ?? "?" }.joined(separator: " \u{B7} ")
    }

    private static func number(of display: [String: Any], in spaces: [[String: Any]]) -> Int? {
        guard let current = display["Current Space"] as? [String: Any],
              let currentID = spaceID(current), currentID != 0 else { return nil }
        let ids = spaces.map(spaceID)
        // An unreadable entry or a repeated current ID makes the position untrustworthy.
        guard !ids.contains(where: { $0 == nil }),
              let index = ids.firstIndex(of: currentID),
              ids.lastIndex(of: currentID) == index else { return nil }
        return index + 1
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        guard let n = space["ManagedSpaceID"] as? NSNumber,
              !CFNumberIsFloatType(n) else { return nil }
        return n.uint64Value
    }
}
