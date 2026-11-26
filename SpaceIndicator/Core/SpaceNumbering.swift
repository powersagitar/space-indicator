import Foundation

enum SpaceNumbering {
    /// 1-based position of the active Space within its display's "Spaces" array.
    static func number(activeSpaceID: UInt64, displays: [[String: Any]]) -> Int? {
        guard activeSpaceID != 0 else { return nil }
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.map(spaceID)
            guard let index = ids.firstIndex(of: activeSpaceID) else { continue }
            // An unreadable entry makes the position untrustworthy.
            if ids.contains(where: { $0 == nil }) { return nil }
            return index + 1
        }
        return nil
    }

    static func title(for number: Int?) -> String {
        number.map { "\($0)" } ?? "?"
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        guard let n = space["ManagedSpaceID"] as? NSNumber,
              !CFNumberIsFloatType(n) else { return nil }
        return n.uint64Value
    }
}
