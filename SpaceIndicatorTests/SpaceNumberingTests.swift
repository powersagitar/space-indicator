import Foundation
import Testing

private func space(_ id: Any, type: Int = 0) -> [String: Any] {
    ["ManagedSpaceID": id, "type": type]
}

private func display(_ spaces: [[String: Any]]) -> [String: Any] {
    ["Display Identifier": "Main", "Spaces": spaces]
}

@Suite struct SpaceNumberingTests {
    @Test func singleDisplay() {
        let d = [display([space(10), space(11), space(12)])]
        #expect(SpaceNumbering.number(activeSpaceID: 11, displays: d) == 2)
    }

    @Test func fullScreenCountsByPosition() {
        let d = [display([space(10), space(11), space(50, type: 4), space(12)])]
        #expect(SpaceNumbering.number(activeSpaceID: 50, displays: d) == 3)
        #expect(SpaceNumbering.number(activeSpaceID: 12, displays: d) == 4)
    }

    @Test func separateSpacesSecondDisplay() {
        let d = [display([space(10), space(11)]), display([space(20), space(21), space(22)])]
        #expect(SpaceNumbering.number(activeSpaceID: 22, displays: d) == 3)
        #expect(SpaceNumbering.number(activeSpaceID: 10, displays: d) == 1)
    }

    @Test func activeMissingIsNil() {
        let d = [display([space(10), space(11)])]
        #expect(SpaceNumbering.number(activeSpaceID: 99, displays: d) == nil)
        #expect(SpaceNumbering.number(activeSpaceID: 0, displays: d) == nil)
        #expect(SpaceNumbering.number(activeSpaceID: 10, displays: []) == nil)
    }

    @Test func idsReadFromAnyIntegerNSNumber() {
        let d = [display([
            space(NSNumber(value: Int64(10))),
            space(NSNumber(value: UInt64(11))),
            space(NSNumber(value: Int32(12))),
        ])]
        #expect(SpaceNumbering.number(activeSpaceID: 12, displays: d) == 3)
    }

    @Test func skipsMalformedOtherDisplay() {
        let d: [[String: Any]] = [["Display Identifier": "X"], display([space(10), space(11)])]
        #expect(SpaceNumbering.number(activeSpaceID: 11, displays: d) == 2)
    }

    @Test func unreadableEntryOnActiveDisplayIsNil() {
        let d = [display([space(10), space("bad"), space(12)])]
        #expect(SpaceNumbering.number(activeSpaceID: 12, displays: d) == nil)
    }

    @Test func titleFormatting() {
        #expect(SpaceNumbering.title(for: 3) == "3")
        #expect(SpaceNumbering.title(for: nil) == "?")
    }
}
