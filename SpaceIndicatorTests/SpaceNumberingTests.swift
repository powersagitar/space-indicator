import Foundation
import Testing

private func space(_ id: Any, type: Int = 0) -> [String: Any] {
    ["ManagedSpaceID": id, "type": type]
}

private func display(_ spaces: [[String: Any]], current: Any? = nil, id: String = "Main") -> [String: Any] {
    var d: [String: Any] = ["Display Identifier": id, "Spaces": spaces]
    if let current { d["Current Space"] = ["ManagedSpaceID": current] }
    return d
}

@Suite struct SpaceNumberingTests {
    private func numbers(_ d: [[String: Any]], order: [String] = []) -> [Int?] {
        SpaceNumbering.numbers(displays: d, screenOrder: order)
    }

    @Test func singleDisplay() {
        #expect(numbers([display([space(10), space(11), space(12)], current: 11)]) == [2])
    }

    /// "Displays have separate Spaces" off: CGS lists one `Main` entry, which matches none
    /// of the screens' UUIDs, so two screens still give one number.
    @Test func mainSingleArrayOneNumber() {
        let order = ["37D8832A-2D66-02CA-B9F7-8F30A301B230", "5D1C6A3E-1F0B-4C2E-9A7D-2B8E4F6A1C90"]
        let d = [display([space(10), space(11), space(20)], current: 20, id: "Main")]
        #expect(numbers(d, order: order) == [3])
    }

    @Test func fullScreenCountsByPosition() {
        let spaces = [space(10), space(11), space(50, type: 4), space(12)]
        #expect(numbers([display(spaces, current: 50)]) == [3])
        #expect(numbers([display(spaces, current: 12)]) == [4])
    }

    @Test func eachDisplayHasItsOwnNumber() {
        let d = [
            display([space(10), space(11)], current: 10, id: "A"),
            display([space(20), space(21), space(22)], current: 22, id: "B"),
        ]
        #expect(numbers(d) == [1, 3])
    }

    @Test func orderedByScreenOrderUnknownLast() {
        let d = [
            display([space(10), space(11)], current: 11, id: "A"),
            display([space(20), space(21)], current: 20, id: "B"),
            display([space(30), space(31), space(32)], current: 32, id: "C"),
        ]
        #expect(numbers(d, order: ["B", "A"]) == [1, 2, 3])
        #expect(numbers(d, order: ["C"]) == [3, 2, 1])
    }

    @Test func missingOrUnknownCurrentIsNil() {
        let spaces = [space(10), space(11)]
        #expect(numbers([display(spaces)]) == [nil])
        #expect(numbers([display(spaces, current: 0)]) == [nil])
        #expect(numbers([display(spaces, current: 99)]) == [nil])
        #expect(numbers([]) == [])
    }

    @Test func idsReadFromAnyIntegerNSNumber() {
        let spaces = [
            space(NSNumber(value: Int64(10))),
            space(NSNumber(value: UInt64(11))),
            space(NSNumber(value: Int32(12))),
        ]
        #expect(numbers([display(spaces, current: NSNumber(value: Int32(12)))]) == [3])
        #expect(numbers([display(spaces, current: NSNumber(value: 11.0))]) == [nil])
    }

    @Test func boolIDsAreUnreadable() {
        let spaces = [space(10), space(NSNumber(value: true)), space(12)]
        #expect(numbers([display(spaces, current: 12)]) == [nil])
        #expect(numbers([display([space(1), space(2)], current: NSNumber(value: true))]) == [nil])
    }

    @Test func floatEntryInSpacesMakesThatDisplayNil() {
        let d = [
            display([space(10), space(NSNumber(value: 11.0)), space(12)], current: 12, id: "A"),
            display([space(20), space(21)], current: 21, id: "B"),
        ]
        #expect(numbers(d) == [nil, 2])
    }

    @Test func identifiedDisplayWithoutSpacesIsNil() {
        let d: [[String: Any]] = [
            ["Display Identifier": "X"],
            ["Display Identifier": "Y", "Spaces": "bad"],
            display([space(10), space(11)], current: 11),
        ]
        #expect(numbers(d) == [nil, nil, 2])
    }

    @Test func skipsDisplayWithNeitherIdentifierNorSpaces() {
        let d: [[String: Any]] = [["Current Space": ["ManagedSpaceID": 1]], display([space(10), space(11)], current: 11)]
        #expect(numbers(d) == [2])
    }

    @Test func unreadableEntryMakesThatDisplayNil() {
        let d = [
            display([space(10), space("bad"), space(12)], current: 12, id: "A"),
            display([space(20), space(21)], current: 21, id: "B"),
        ]
        #expect(numbers(d) == [nil, 2])
    }

    @Test func duplicateCurrentIDMakesThatDisplayNil() {
        let d = [
            display([space(10), space(11), space(10)], current: 10, id: "A"),
            display([space(20), space(21)], current: 21, id: "B"),
        ]
        #expect(numbers(d) == [nil, 2])
    }

    @Test func titleFormatting() {
        #expect(SpaceNumbering.title(for: [2, 1]) == "2 \u{B7} 1")
        #expect(SpaceNumbering.title(for: [3]) == "3")
        #expect(SpaceNumbering.title(for: [3, nil]) == "3 \u{B7} ?")
        #expect(SpaceNumbering.title(for: []) == "?")
    }
}
