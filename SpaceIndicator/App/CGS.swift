import AppKit

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

// "Copy" returns +1. Swift treats an @_silgen_name function's object return as owned (+1)
// and releases it, which matches here. Don't reuse this pattern for +0 "Get" functions:
// Swift would over-release their result.
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

enum CGS {
    /// Each display's current Space number, left to right.
    @MainActor
    static func spaceNumbers() -> [Int?] {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()),
              let displays = raw as? [[String: Any]]
        else { return [] }
        return SpaceNumbering.numbers(displays: displays, screenOrder: screenOrder())
    }

    /// Display UUID strings (the format of CGS's "Display Identifier"), left to right.
    @MainActor
    private static func screenOrder() -> [String] {
        NSScreen.screens
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            .compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
                else { return nil }
                return CFUUIDCreateString(nil, uuid) as String?
            }
    }
}
