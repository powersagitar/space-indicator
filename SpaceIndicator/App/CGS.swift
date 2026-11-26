import Foundation

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

enum CGS {
    static func activeSpaceNumber() -> Int? {
        let cid = CGSMainConnectionID()
        let active = CGSGetActiveSpace(cid)
        guard let raw = CGSCopyManagedDisplaySpaces(cid),
            let displays = raw as? [[String: Any]]
        else { return nil }
        return SpaceNumbering.number(activeSpaceID: active, displays: displays)
    }
}
