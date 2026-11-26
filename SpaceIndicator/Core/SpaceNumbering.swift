import Foundation

enum SpaceNumbering {
    /// One entry per display: the 1-based position of its "Current Space" within its own
    /// "Spaces" array, or nil when that can't be trusted. Displays listed in `screenOrder`
    /// (by "Display Identifier") come first, in that order; the rest keep CGS order.
    /// A display with an identifier but no readable "Spaces" is nil; a dict with neither is skipped.
    static func numbers(displays: [[String: Any]], screenOrder: [String]) -> [Int?] {
        var entries: [(id: String?, number: Int?)] = []
        for display in displays {
            let id = display["Display Identifier"] as? String
            if let spaces = display["Spaces"] as? [[String: Any]] {
                entries.append((id, number(of: display, in: spaces)))
            } else if id != nil {
                entries.append((id, nil))
            }
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
        // A Bool bridges to NSNumber (CFBoolean) too, and a float isn't an ID.
        guard let n = space["ManagedSpaceID"] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(n) else { return nil }
        return n.uint64Value
    }
}
